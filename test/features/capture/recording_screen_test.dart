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
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The Recording screen is the one screen in the app that is mostly error
/// states: every way a capture can fail lands here, and each one has to offer
/// the user something to do. These tests walk every arm of its
/// `switch (state.failure)`.
void main() {
  /// Wednesday 2026-03-11, 10:00 local — midweek, far from any boundary.
  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  late FakeAudioRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late FakePermissionService permissions;
  late FakeUsageRepository usage;

  setUp(() {
    recorder = FakeAudioRecorder();
    recognizer = FakeSpeechRecognizer();
    permissions = FakePermissionService();
    usage = FakeUsageRepository();
  });

  tearDown(() => usage.dispose());

  /// Boots the Recording screen inside a router that also owns the two places
  /// it can send the user: Home, and Confirm.
  Future<GoRouter> pumpRecording(
    WidgetTester tester, {
    CaptureState? seed,
  }) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = GoRouter(
      initialLocation: '/capture',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => const RecordingScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'confirm',
              builder: (_, _) => const Scaffold(body: Text('confirm screen')),
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
            permissions: permissions,
          ),
          // ⚠️ The pipeline reads the usage repository the moment the
          // controller touches it, and the real one opens a drift database —
          // which deadlocks inside `testWidgets`' FakeAsync.
          usageRepositoryProvider.overrideWithValue(usage),
          primaryTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          fallbackTaskExtractorProvider.overrideWithValue(FakeTaskExtractor()),
          if (seed != null)
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
    await pumpSettled(tester);
    return router;
  }

  CaptureState stateOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    ).read(captureControllerProvider);
  }

  /// ⚠️ Unmounts the tree **inside** the test body. The orb and the waveform
  /// animate forever and the pipeline holds a 200 ms ticker; flutter_test
  /// asserts on pending timers before any teardown callback runs, so a tree
  /// left standing reports "A Timer is still pending" from the wrong place.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('while recording', () {
    testWidgets('renders the timer, the orb, the waveform and the hint', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.recording),
      );

      expect(find.text('Recording...'), findsOneWidget);
      expect(find.byType(RecordingTimer), findsOneWidget);
      expect(find.byType(MicOrb), findsOneWidget);
      expect(find.byType(WaveformView), findsOneWidget);
      expect(
        find.text('Speak naturally.\nYou can say multiple tasks at once.'),
        findsOneWidget,
      );

      await shutdown(tester);
    });

    testWidgets('Stop is offered only while the microphone is open', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.recording),
      );
      expect(
        tester.getSemantics(find.byType(DangerButton)),
        isSemantics(label: 'Stop', isButton: true, isEnabled: true),
      );
      await shutdown(tester);

      // Stop has already been pressed and the pipeline is transcribing: a
      // second press has nothing to stop, and the controller would drop it.
      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.transcribing),
      );
      expect(
        tester.getSemantics(find.byType(DangerButton)),
        isSemantics(label: 'Stop', isButton: true, isEnabled: false),
      );

      handle.dispose();
      await shutdown(tester);
    });

    testWidgets('a live partial transcript replaces the hint', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.recording,
          transcript: 'call the dentist tomorrow',
        ),
      );

      expect(find.text('call the dentist tomorrow'), findsOneWidget);
      expect(
        find.text('Speak naturally.\nYou can say multiple tasks at once.'),
        findsNothing,
      );

      await shutdown(tester);
    });

    testWidgets('Cancel tears the capture down and routes Home', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.recording),
      );

      await tester.tap(find.byType(SecondaryButton));
      await pumpSettled(tester);

      expect(find.text('home screen'), findsOneWidget);
      expect(recorder.cancelled, isTrue);
      expect(recognizer.cancelled, isTrue);
      expect(stateOf(tester).phase, CapturePhase.idle);

      await shutdown(tester);
    });

    testWidgets('back cancels the session rather than popping a live page', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.recording),
      );

      await tester.tap(find.byType(IconButton));
      await pumpSettled(tester);

      expect(find.text('home screen'), findsOneWidget);
      expect(recorder.cancelled, isTrue);

      await shutdown(tester);
    });
  });

  group('a refused microphone', () {
    testWidgets('offers Allow while the OS is still willing to prompt', (
      WidgetTester tester,
    ) async {
      permissions.set(AppPermission.microphone, PermissionState.denied);
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.failed,
          failure: PermissionFailure('denied', permanentlyDenied: false),
        ),
      );

      expect(find.text('Tasuke needs your microphone'), findsOneWidget);
      expect(
        find.text(
          "It's used only while you're recording a task, and the audio never "
          'leaves this device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsOneWidget);

      await tester.tap(find.byType(PrimaryButton));
      await pumpSettled(tester);

      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);

      await shutdown(tester);
    });

    testWidgets('permanently denied opens Settings and never re-requests', (
      WidgetTester tester,
    ) async {
      permissions.set(
        AppPermission.microphone,
        PermissionState.permanentlyDenied,
      );
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.failed,
          failure: PermissionFailure('denied', permanentlyDenied: true),
        ),
      );

      expect(
        find.text(
          'Microphone access is off for Tasuke AI. You can turn it back on '
          'in Settings.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);

      await tester.tap(find.byType(PrimaryButton));
      await pumpSettled(tester);

      // ⚠️ The single most important assertion in this file. Re-requesting a
      // permanently denied permission silently no-ops on iOS, so a CTA that
      // asked again would be a button that does nothing — which reads as a
      // broken app rather than as a setting the user has to change.
      expect(permissions.settingsOpened, 1);
      expect(permissions.requested, isEmpty);

      await shutdown(tester);
    });
  });

  group('every other failure', () {
    /// One row per arm of `_CaptureError`'s switch, with the copy the ARB
    /// promises for it. "Some error is on screen" would pass for all of them.
    final List<(String, Failure, String, String)> arms =
        <(String, Failure, String, String)>[
          (
            'a microphone another app is holding',
            const RecordingFailure('busy', kind: RecordingFailureKind.busy),
            'Your microphone is in use',
            'Another app or a call is using it. Try again in a moment.',
          ),
          (
            'a clip too short to be speech',
            const RecordingFailure(
              'too short',
              kind: RecordingFailureKind.tooShort,
            ),
            "We didn't catch that",
            'Hold on — say a bit more.',
          ),
          (
            'a speech model that will not load',
            const TranscriptionFailure(
              'no model',
              kind: TranscriptionFailureKind.modelUnavailable,
            ),
            "The voice model isn't ready",
            "Tasuke AI couldn't load its speech model. You can still type a "
                'task.',
          ),
          (
            'an utterance that carried no speech',
            const TranscriptionFailure(
              'silence',
              kind: TranscriptionFailureKind.noSpeech,
            ),
            "We didn't catch that",
            'Try again a little closer to the microphone.',
          ),
          (
            'an extractor that is still downloading',
            const ExtractionFailure(
              'not installed',
              kind: ExtractionFailureKind.modelNotInstalled,
            ),
            'The AI is still downloading',
            'Voice capture unlocks once the model finishes. You can add tasks '
                'by hand in the meantime.',
          ),
          (
            'anything the screen has no copy for',
            const StorageFailure('write failed'),
            'Something went wrong',
            'Please try again.',
          ),
        ];

    for (final (String what, Failure failure, String title, String body)
        in arms) {
      testWidgets('$what gets its own title and body', (
        WidgetTester tester,
      ) async {
        await pumpRecording(
          tester,
          seed: CaptureState(phase: CapturePhase.failed, failure: failure),
        );

        expect(find.text(title), findsOneWidget);
        expect(find.text(body), findsOneWidget);

        // ⚠️ Every arm, without exception. A user who just spoke and was told
        // "no" must never be left with nothing to do but say it again.
        expect(find.text('Type a task instead'), findsOneWidget);

        await shutdown(tester);
      });
    }

    testWidgets('"Type a task instead" opens Confirm on a blank manual draft', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.failed,
          failure: TranscriptionFailure(
            'silence',
            kind: TranscriptionFailureKind.noSpeech,
          ),
        ),
      );

      await tester.tap(find.text('Type a task instead'));
      await pumpSettled(tester);

      expect(find.text('confirm screen'), findsOneWidget);

      final CaptureState state = stateOf(tester);
      expect(state.phase, CapturePhase.confirming);
      final TaskDraft draft = state.drafts.single;
      expect(draft.title, isEmpty);
      expect(draft.source, TaskSource.manual);

      await shutdown(tester);
    });

    testWidgets('"Try again" re-opens the microphone', (
      WidgetTester tester,
    ) async {
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.failed,
          failure: RecordingFailure('busy', kind: RecordingFailureKind.busy),
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await pumpSettled(tester);

      expect(stateOf(tester).phase, CapturePhase.recording);
      expect(recorder.started, isTrue);
      expect(find.byType(MicOrb), findsOneWidget);

      // ⚠️ Nothing is awaited on the way out. Unmounting disposes the provider
      // scope, and the pipeline cancels its 200 ms ticker synchronously from
      // there; awaiting a teardown instead would block on a stream close that
      // FakeAsync never delivers.
      await shutdown(tester);
    });
  });
}
