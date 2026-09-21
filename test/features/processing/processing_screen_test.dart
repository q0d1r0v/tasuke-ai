import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/processing/presentation/processing_screen.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The "Turning your thoughts into tasks..." screen.
///
/// Almost all of its behaviour is the relationship between two clocks — the
/// pipeline's real progress and the minimum dwell the rows are paced by — so
/// that is what these tests drive.
void main() {
  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  /// Four rows × 380 ms. Restated rather than imported so a change to the
  /// design constant has to be made deliberately here too.
  const Duration wholeDwell = Duration(milliseconds: 380 * 4);

  late FakeAudioRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late FakeUsageRepository usage;

  setUp(() {
    recorder = FakeAudioRecorder();
    recognizer = FakeSpeechRecognizer();
    usage = FakeUsageRepository();
  });

  tearDown(() => usage.dispose());

  /// Boots the Processing screen.
  ///
  /// [overHome] pushes it on top of Home instead of making it the first route,
  /// which is what the back test needs: this screen's pop handler really does
  /// pop, and a route with nothing under it has nowhere to go.
  Future<GoRouter> pumpProcessing(
    WidgetTester tester, {
    required CaptureState seed,
    bool overHome = false,
  }) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = GoRouter(
      initialLocation: overHome ? '/home' : '/capture/processing',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => const Scaffold(body: Text('recording screen')),
          routes: <RouteBase>[
            GoRoute(
              path: 'processing',
              builder: (_, _) => const ProcessingScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            clock: clock,
            recorder: recorder,
            recognizer: recognizer,
          ),
          // ⚠️ The pipeline reads the usage repository as soon as the
          // controller touches it, and the real one opens a drift database —
          // which deadlocks inside `testWidgets`' FakeAsync.
          usageRepositoryProvider.overrideWithValue(usage),
          primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          captureControllerProvider.overrideWithBuild(
            (Ref ref, CaptureController notifier) => seed,
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    // A single frame, so a dwell assertion is measured from zero rather than
    // from however long a settle happened to take.
    await tester.pump();

    if (overHome) {
      unawaited(router.push<void>('/capture/processing'));
      await pumpSettled(tester);
    }
    return router;
  }

  CaptureController controllerOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    ).read(captureControllerProvider.notifier);
  }

  CaptureState stateOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    ).read(captureControllerProvider);
  }

  List<ProcessingStepView> stepsOf(WidgetTester tester) {
    return tester
        .widget<ProcessingChecklist>(find.byType(ProcessingChecklist))
        .steps;
  }

  int doneCount(WidgetTester tester) {
    return stepsOf(tester)
        .where((ProcessingStepView s) => s.state == ProcessingStepState.done)
        .length;
  }

  /// ⚠️ Unmounts the tree **inside** the test body: the orb never stops
  /// animating, and flutter_test asserts on pending timers before teardown.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('renders the title and all four steps of the checklist', (
    WidgetTester tester,
  ) async {
    await pumpProcessing(
      tester,
      seed: const CaptureState(phase: CapturePhase.transcribing),
    );

    expect(find.text('Turning your thoughts into tasks...'), findsOneWidget);
    expect(stepsOf(tester).map((ProcessingStepView s) => s.label), <String>[
      'Transcribing your voice',
      'Understanding with AI',
      'Finding tasks and dates',
      'Almost done...',
    ]);

    await shutdown(tester);
  });

  testWidgets('a pipeline that finishes instantly still walks the rows down', (
    WidgetTester tester,
  ) async {
    await pumpProcessing(
      tester,
      seed: const CaptureState(phase: CapturePhase.transcribing),
    );

    // ⚠️ On a fast device transcription and extraction both finish in well
    // under a second. Four rows going green at once reads as a glitch rather
    // than as work being done, so the rows are paced by a minimum dwell too.
    controllerOf(tester).state = const CaptureState(
      phase: CapturePhase.confirming,
    );
    await tester.pump();
    expect(doneCount(tester), lessThan(4));

    await tester.pump(wholeDwell);
    expect(doneCount(tester), 4);

    await shutdown(tester);
  });

  testWidgets('the rows never run ahead of the pipeline either', (
    WidgetTester tester,
  ) async {
    await pumpProcessing(
      tester,
      seed: const CaptureState(phase: CapturePhase.transcribing),
    );

    // The dwell is long over, but the model is still chewing on the
    // transcript: the checklist has to wait for it.
    await tester.pump(wholeDwell * 2);
    expect(doneCount(tester), lessThan(4));

    controllerOf(tester).state = const CaptureState(
      phase: CapturePhase.confirming,
    );
    await tester.pump();
    expect(doneCount(tester), 4);

    await shutdown(tester);
  });

  testWidgets('back cancels the session rather than popping a live page', (
    WidgetTester tester,
  ) async {
    await pumpProcessing(
      tester,
      seed: const CaptureState(
        phase: CapturePhase.extracting,
        transcript: 'call the dentist tomorrow',
      ),
      overHome: true,
    );
    expect(find.byType(ProcessingScreen), findsOneWidget);

    unawaited(
      Navigator.of(tester.element(find.byType(ProcessingScreen))).maybePop(),
    );
    await pumpSettled(tester);

    expect(find.text('home screen'), findsOneWidget);
    expect(recorder.cancelled, isTrue);
    expect(recognizer.cancelled, isTrue);
    expect(stateOf(tester).phase, CapturePhase.idle);

    await shutdown(tester);
  });
}
