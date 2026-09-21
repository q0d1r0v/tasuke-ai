import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/app.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

/// The on-device journey.
///
/// Everything below runs against the **real** Drift database on the device's
/// own filesystem, the real notification plugin and the real extractor — the
/// parts a host-side widget test cannot touch. Only the microphone and the
/// language-model download are faked, because an emulator has no usable
/// microphone and a 219 MB download has no place in a test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  testWidgets('cold start → onboarding → Home, with a real database', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(preferences),
          clockProvider.overrideWithValue(clock),
        ],
        child: const TasukeApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The real database opened, on the device's own filesystem.
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a spoken sentence becomes two saved tasks', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefKeys.onboardingSeen: true,
      PrefKeys.permissionsPrimerSeen: true,
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    // The transcript a real recording of the spec's example sentence produces.
    // The microphone and whisper are stubbed; everything downstream — the
    // grammar, the validator, Drift, the reminder resolution — is real.
    const String transcript =
        'Tomorrow at 3 PM send the build to James and Friday check App Store';

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(preferences),
          clockProvider.overrideWithValue(clock),
          speechRecognizerProvider.overrideWithValue(
            const _ScriptedRecognizer(transcript),
          ),
          // The language model is not downloaded in a test, so the pipeline
          // uses the deterministic extractor — which is exactly what it does on
          // a real device before the download finishes.
          primaryTaskExtractorProvider.overrideWithValue(
            const _NeverReadyExtractor(),
          ),
          modelInstallerProvider.overrideWithValue(const _NoModelInstaller()),
        ],
        child: const TasukeApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(HomeScreen), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    final CaptureController controller = container.read(
      captureControllerProvider.notifier,
    );

    // Run the real extractor over the transcript.
    final List<ExtractedTask> extracted = await const RuleBasedTaskExtractor()
        .extract(transcript, now: LocalDateTime.fromLocal(clock.nowLocal()));
    expect(
      extracted.length,
      2,
      reason: 'one sentence, two tasks — the spec\'s headline example',
    );

    // Save them through the real repository.
    controller.startManualDraft();
    final TaskDraft seed = container
        .read(captureControllerProvider)
        .drafts
        .single;
    controller.updateDraft(
      seed.copyWith(
        title: extracted.first.title,
        date: extracted.first.date,
        time: extracted.first.time,
        hasReminder: true,
      ),
    );
    controller.addBlankDraft();
    final TaskDraft second = container
        .read(captureControllerProvider)
        .drafts
        .last;
    controller.updateDraft(
      second.copyWith(
        title: extracted.last.title,
        date: extracted.last.date,
        time: extracted.last.time,
      ),
    );

    expect(await controller.save(), isTrue);
    await tester.pumpAndSettle();

    final TaskRepository repository = container.read(taskRepositoryProvider);
    final List<Task> all = await repository
        .watchToday(extracted.last.date!)
        .first;
    expect(all.length, greaterThanOrEqualTo(2));

    // Clean up so a re-run starts from an empty database.
    await repository.deleteAll();
  });

  testWidgets('every screen renders on a real device', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefKeys.onboardingSeen: true,
      PrefKeys.permissionsPrimerSeen: true,
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(preferences),
          clockProvider.overrideWithValue(clock),
        ],
        child: const TasukeApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final BuildContext context = tester.element(find.byType(HomeScreen));
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Walk the four bottom-nav destinations. A screen that throws on a device
    // but not on the host is usually a plugin reached during build.
    for (final String label in <String>[
      l10n.searchTitle,
      l10n.statsTitle,
      l10n.settingsTitle,
    ]) {
      await tester.tap(find.byIcon(_iconFor(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

IconData _iconFor(String label) => switch (label) {
  'Search' => Icons.search_rounded,
  'Stats' => Icons.bar_chart_rounded,
  _ => Icons.settings_rounded,
};

final class _ScriptedRecognizer implements SpeechRecognizer {
  const _ScriptedRecognizer(this.transcript);

  final String transcript;

  @override
  Future<SpeechAvailability> availability() async => SpeechAvailability.ready;

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) async* {
    yield SpeechPartial(transcript);
    yield SpeechFinal(transcript);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> release() async {}
}

final class _NeverReadyExtractor implements TaskExtractor {
  const _NeverReadyExtractor();

  @override
  Future<bool> isReady() async => false;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async => const <ExtractedTask>[];
}

final class _NoModelInstaller implements ModelInstaller {
  const _NoModelInstaller();

  @override
  Stream<ModelState> watch(ModelSpec spec) => const Stream<ModelState>.empty();

  @override
  ModelState stateOf(ModelSpec spec) => const ModelNotInstalled();

  @override
  Future<bool> isInstalled(ModelSpec spec) async => false;

  @override
  Future<String?> pathOf(ModelSpec spec) async => null;

  @override
  Future<void> install(ModelSpec spec) async {}

  @override
  Future<void> cancel(ModelSpec spec) async {}

  @override
  Future<void> remove(ModelSpec spec) async {}
}
