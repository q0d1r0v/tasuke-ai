import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/router/app_navigator.dart';
import 'package:tasuke_ai/app/router/reminder_routing.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// Hands the microphone back only once [handBack] completes: the native
/// teardown that takes seconds, or never ends behind a wedged one.
final class _SlowRecorder implements AudioRecorder {
  _SlowRecorder(this.inner);

  final FakeAudioRecorder inner;
  final Completer<void> handBack = Completer<void>();

  @override
  Future<bool> hasPermission() => inner.hasPermission();

  @override
  Future<bool> isRecording() => inner.isRecording();

  @override
  Future<Stream<Uint8List>> start() => inner.start();

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> cancel() async {
    await handBack.future;
    await inner.cancel();
  }

  @override
  Future<void> dispose() => inner.dispose();
}

/// A quota read that waits on [gate], which parks `begin()` in checkingQuota.
final class _HeldUsage implements UsageRepository {
  _HeldUsage(this.inner, this.gate);

  final FakeUsageRepository inner;
  final Completer<void> gate;

  @override
  Future<DailyUsage> read(LocalDate day) async {
    await gate.future;
    return inner.read(day);
  }

  @override
  Stream<DailyUsage> watchToday(LocalDate today) => inner.watchToday(today);

  @override
  Future<void> recordCapture(LocalDate day, {required int taskCount}) =>
      inner.recordCapture(day, taskCount: taskCount);

  @override
  Future<void> prune(LocalDate today, {int keepDays = 90}) =>
      inner.prune(today, keepDays: keepDays);
}

/// A microphone prompt left unanswered until [gate] completes, which parks
/// `begin()` in requestingPermission.
final class _HeldPermissions implements PermissionService {
  _HeldPermissions(this.gate);

  final FakePermissionService inner = FakePermissionService();
  final Completer<void> gate;

  @override
  Future<PermissionState> status(AppPermission permission) async {
    await gate.future;
    return inner.status(permission);
  }

  @override
  Future<PermissionState> request(AppPermission permission) =>
      inner.request(permission);

  @override
  Future<bool> openSettings() => inner.openSettings();
}

/// The capture pipeline over whichever ports a test wants to hold.
Override _pipelineOver({
  AudioRecorder? recorder,
  PermissionService? permissions,
  UsageRepository? usage,
}) => voiceCapturePipelineProvider.overrideWith(
  (Ref ref) => VoiceCapturePipeline(
    recorder: recorder ?? ref.watch(audioRecorderProvider),
    recognizer: ref.watch(speechRecognizerProvider),
    primaryExtractor: FakeTaskExtractor(),
    fallbackExtractor: FakeTaskExtractor(),
    permissions: permissions ?? ref.watch(permissionServiceProvider),
    usage: usage ?? ref.watch(usageRepositoryProvider),
    clock: ref.watch(clockProvider),
    newDraftId: () => 'draft',
  ),
);

/// A reminder tapped while the app is already running.
void main() {
  late FakeLocalNotifier notifier;
  late FakeAudioRecorder recorder;
  late FakeUsageRepository usage;
  late List<String> opened;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefKeys.onboardingSeen: true,
      PrefKeys.permissionsPrimerSeen: true,
    });
    notifier = FakeLocalNotifier();
    recorder = FakeAudioRecorder();
    usage = FakeUsageRepository();
    opened = <String>[];
  });

  // ⚠️ Closed here, not in the test body: awaiting a stream close inside
  // `FakeAsync` can deadlock.
  tearDown(() {
    notifier.dispose();
    usage.dispose();
  });

  Future<ProviderContainer> pumpRouting(
    WidgetTester tester, {
    CaptureState? capture,
    List<Override> overrides = const <Override>[],
  }) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            notifier: notifier,
            recorder: recorder,
            preferences: preferences,
          ),
          usageRepositoryProvider.overrideWithValue(usage),
          primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          appBootstrapProvider.overrideWith(
            (Ref ref) async => const BootstrapResult(),
          ),
          reminderOpenerProvider.overrideWithValue(opened.add),
          if (capture != null)
            captureControllerProvider.overrideWithBuild(
              (Ref ref, CaptureController controller) => capture,
            ),
          ...overrides,
        ],
        child: const ReminderRouting(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(
      tester.element(find.byType(SizedBox)),
      listen: false,
    );
  }

  /// Delivers a tap and lets its post-frame navigation run.
  Future<void> tap(WidgetTester tester, String taskId) async {
    notifier.emitTap(encodeReminderPayload(taskId));
    await tester.idle();
    await tester.pump();
    await tester.idle();
  }

  testWidgets('a tap opens its task', (WidgetTester tester) async {
    await pumpRouting(tester);

    await tap(tester, 't-1');

    expect(opened, <String>['t-1']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a second tap on the same task opens it again', (
    WidgetTester tester,
  ) async {
    // ⚠️ Every tap on one task carries the identical payload, and riverpod
    // drops a value equal to the last one. The second tap used to do nothing.
    await pumpRouting(tester);

    await tap(tester, 't-1');
    await tap(tester, 't-1');

    expect(opened, <String>['t-1', 't-1']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('during a capture', () {
    testWidgets('a recording is cancelled before the task opens', (
      WidgetTester tester,
    ) async {
      // ⚠️ `go('/home')` removes the Recording page without its PopScope, the
      // only thing that cancels. The mic stayed open off screen.
      final ProviderContainer container = await pumpRouting(
        tester,
        capture: const CaptureState(phase: CapturePhase.recording),
      );

      await tap(tester, 't-1');

      expect(recorder.cancelled, isTrue);
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.idle,
      );
      expect(opened, <String>['t-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed capture is reset, so the mic button works again', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpRouting(
        tester,
        capture: const CaptureState(phase: CapturePhase.failed),
      );

      await tap(tester, 't-1');

      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.idle,
      );
      expect(opened, <String>['t-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'the task opens without waiting for the mic to be handed back',
      (WidgetTester tester) async {
        // ⚠️ `cancel()` goes idle at once, but its teardown can take seconds.
        // Awaited, the router took the user Home straight away and the task
        // opened seconds later over whatever they had moved on to.
        final _SlowRecorder slow = _SlowRecorder(recorder);
        final ProviderContainer container = await pumpRouting(
          tester,
          capture: const CaptureState(phase: CapturePhase.recording),
          overrides: <Override>[_pipelineOver(recorder: slow)],
        );

        await tap(tester, 't-1');

        expect(opened, <String>['t-1']);
        expect(
          container.read(captureControllerProvider).phase,
          CapturePhase.idle,
        );
        expect(recorder.cancelled, isFalse, reason: 'still handing it back');

        slow.handBack.complete();
        await tester.idle();

        expect(recorder.cancelled, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final CapturePhase phase in <CapturePhase>[
      CapturePhase.checkingQuota,
      CapturePhase.requestingPermission,
    ]) {
      testWidgets('a begin() still in $phase gives up, and the task opens', (
        WidgetTester tester,
      ) async {
        // The tap used to be dropped here. `begin()` re-checks for a cancel
        // after each await, so it must return null and never open the mic.
        final Completer<void> gate = Completer<void>();
        final ProviderContainer container = await pumpRouting(
          tester,
          overrides: <Override>[
            if (phase == CapturePhase.checkingQuota)
              _pipelineOver(usage: _HeldUsage(usage, gate))
            else
              _pipelineOver(permissions: _HeldPermissions(gate)),
          ],
        );
        String? location = 'not returned yet';
        unawaited(
          container
              .read(captureControllerProvider.notifier)
              .begin()
              .then((String? to) => location = to),
        );
        await tester.idle();
        expect(container.read(captureControllerProvider).phase, phase);

        await tap(tester, 't-1');

        expect(opened, <String>['t-1']);
        expect(
          container.read(captureControllerProvider).phase,
          CapturePhase.idle,
        );

        gate.complete();
        await tester.idle();

        expect(location, isNull);
        expect(recorder.started, isFalse);
        expect(
          container.read(captureControllerProvider).phase,
          CapturePhase.idle,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('processing is left running, and the task opens', (
      WidgetTester tester,
    ) async {
      await pumpRouting(
        tester,
        capture: const CaptureState(phase: CapturePhase.extracting),
      );

      await tap(tester, 't-1');

      expect(recorder.cancelled, isFalse);
      expect(opened, <String>['t-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('nothing opens before onboarding is finished', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpRouting(tester);

    await tap(tester, 't-1');

    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
