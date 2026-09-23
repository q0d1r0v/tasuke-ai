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
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

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
    FakePurchaseGateway? purchases,
    UsageRepository? usageRepository,
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
          path: '/paywall',
          builder: (_, GoRouterState state) => Scaffold(
            body: Text('paywall ${state.uri.queryParameters['reason']}'),
          ),
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
            purchases: purchases,
          ),
          // ⚠️ The pipeline reads the usage repository the moment the
          // controller touches it, and the real one opens a drift database —
          // which deadlocks inside `testWidgets`' FakeAsync.
          usageRepositoryProvider.overrideWithValue(usageRepository ?? usage),
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

      // ⚠️ Stop has been pressed and the pipeline is finalising. The controls
      // are REPLACED by a spinner, not greyed out. Two dead buttons under a
      // title that still said "Recording..." over a timer that kept counting
      // is exactly what got reported as "stop doesn't work" — the app looked
      // hung during the one wait it actually has.
      await pumpRecording(
        tester,
        seed: const CaptureState(phase: CapturePhase.transcribing),
      );
      expect(find.byType(DangerButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Finishing up...'), findsWidgets);
      expect(
        find.text('Recording...'),
        findsNothing,
        reason: 'the microphone is closed; saying otherwise is a lie',
      );

      handle.dispose();
      await shutdown(tester);
    });

    for (final CapturePhase phase in <CapturePhase>[
      CapturePhase.checkingQuota,
      CapturePhase.requestingPermission,
    ]) {
      testWidgets(
        'before the mic opens (${phase.name}) the way out stays open',
        (WidgetTester tester) async {
          // ⚠️ This used to render as finalising: "Finishing up..." over a
          // spinner, back disabled, and PopScope eating the iOS swipe. A new
          // capture can wait seconds here for the last one to free the mic.
          final SemanticsHandle handle = tester.ensureSemantics();
          await pumpRecording(tester, seed: CaptureState(phase: phase));

          expect(find.text('Getting ready...'), findsOneWidget);
          expect(find.text('Finishing up...'), findsNothing);
          expect(find.text('Recording...'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            tester.getSemantics(find.byType(SecondaryButton)),
            isSemantics(label: 'Cancel', isButton: true, isEnabled: true),
          );
          expect(
            tester.getSemantics(find.byType(DangerButton)),
            isSemantics(label: 'Stop', isButton: true, isEnabled: false),
          );

          await tester.tap(find.byType(IconButton));
          await pumpSettled(tester);

          final int homes = find.text('home screen').evaluate().length;
          final CapturePhase after = stateOf(tester).phase;
          handle.dispose();
          await shutdown(tester);

          expect(homes, 1);
          expect(after, CapturePhase.idle);
        },
      );
    }

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

    testWidgets('a user who will not grant it can still close and go Home', (
      WidgetTester tester,
    ) async {
      // ⚠️ iOS turns the back swipe off under `PopScope(canPop: false)`, and
      // this view's only button was "Open Settings" — a user who refused the
      // microphone had no way back to their tasks short of killing the app.
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

      await tester.tap(find.byTooltip('Close'));
      await pumpSettled(tester);

      final int homes = find.text('home screen').evaluate().length;
      final CapturePhase phase = stateOf(tester).phase;
      await shutdown(tester);

      expect(homes, 1);
      expect(phase, CapturePhase.idle);
      expect(permissions.requested, isEmpty);
      expect(permissions.settingsOpened, 0);
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
        // Nor with no way out but a retry.
        expect(find.byTooltip('Close'), findsOneWidget);

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
  // ⚠️ A typed task is a capture too (a product decision, 2026-09-23). The
  // "Type a task instead" escape on a failure, offered to a user who had
  // already used the day's capture, saved a second one: 2 of 1 on the Usage
  // screen. `begin` now checks the quota before anything can fail; this is
  // the screen's own backstop.
  group("once today's capture is spent", () {
    /// Wednesday 2026-03-11, the day [clock] is pinned to.
    const LocalDate today = LocalDate(2026, 3, 11);

    const CaptureState stillClosing = CaptureState(
      phase: CapturePhase.failed,
      failure: RecordingFailure(
        'The last capture is still closing',
        kind: RecordingFailureKind.stillClosing,
      ),
    );

    Future<void> spendToday() async {
      for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
        await usage.recordCapture(today, taskCount: 1);
      }
    }

    for (final (String, CaptureState) arm in <(String, CaptureState)>[
      ('still closing', stillClosing),
      (
        'no speech',
        const CaptureState(
          phase: CapturePhase.failed,
          failure: TranscriptionFailure(
            'silence',
            kind: TranscriptionFailureKind.noSpeech,
          ),
        ),
      ),
    ]) {
      testWidgets('a free user is not offered a typed task (${arm.$1})', (
        WidgetTester tester,
      ) async {
        await spendToday();
        await pumpRecording(tester, seed: arm.$2);

        final int escapes = find.text('Type a task instead').evaluate().length;
        final int retries = find.text('Try again').evaluate().length;
        await shutdown(tester);

        expect(escapes, 0);
        expect(retries, 1, reason: 'a way on is still there');
      });
    }

    testWidgets('Try again takes them to the paywall, which says why', (
      WidgetTester tester,
    ) async {
      await spendToday();
      // Answering a frame later, as the database does on a phone: the error
      // view is gone by the time `begin` returns, and a navigation that
      // waited on its context was dropped — the user landed on Home, told
      // nothing.
      await pumpRecording(
        tester,
        seed: stillClosing,
        usageRepository: _SlowUsage(usage),
      );

      await tester.tap(find.text('Try again'));
      // ⚠️ One frame before the quota answers. `pumpSettled` alone runs the
      // clock out first and draws after, so `begin` returned while the error
      // view was still mounted, and this test passed with the bug in place.
      await tester.pump();
      final int errorViews = find.text('Try again').evaluate().length;
      await pumpSettled(tester);

      final int paywalls = find.text('paywall quota').evaluate().length;
      final bool opened = recorder.started;
      await shutdown(tester);

      expect(errorViews, 0, reason: 'the frame that took the context away');
      expect(paywalls, 1);
      expect(opened, isFalse);
    });

    testWidgets('Allow on a refused microphone takes them there too', (
      WidgetTester tester,
    ) async {
      // Rare, as the quota is checked before the prompt, but a subscription
      // that lapsed while the prompt sat refused lands here, and Allow
      // re-runs `begin` the same way Try again does.
      await spendToday();
      await pumpRecording(
        tester,
        seed: const CaptureState(
          phase: CapturePhase.failed,
          failure: PermissionFailure('denied', permanentlyDenied: false),
        ),
        usageRepository: _SlowUsage(usage),
      );

      await tester.tap(find.text('Allow'));
      await tester.pump();
      final int deniedViews = find.text('Allow').evaluate().length;
      await pumpSettled(tester);

      final int paywalls = find.text('paywall quota').evaluate().length;
      final List<AppPermission> asked = permissions.requested;
      await shutdown(tester);

      expect(deniedViews, 0, reason: 'the frame that took the context away');
      expect(paywalls, 1);
      expect(asked, isEmpty, reason: 'no prompt for a capture it cannot make');
    });

    testWidgets('with the capture still unused, the escape is there', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester, seed: stillClosing);

      final int escapes = find.text('Type a task instead').evaluate().length;
      await shutdown(tester);

      expect(escapes, 1);
    });

    testWidgets('a Pro subscriber past the free allowance keeps it', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway pro = FakePurchaseGateway(
        initial: const Entitlement(status: EntitlementStatus.proActive),
      );
      addTearDown(pro.dispose);
      await spendToday();
      await pumpRecording(tester, seed: stillClosing, purchases: pro);

      final int escapes = find.text('Type a task instead').evaluate().length;
      await shutdown(tester);

      expect(escapes, 1);
    });
  });
}

/// [FakeUsageRepository], answering its reads a moment later — long enough
/// for a frame to be drawn while `begin` waits on the quota, as it is on a
/// device.
final class _SlowUsage implements UsageRepository {
  _SlowUsage(this._inner);

  final FakeUsageRepository _inner;

  @override
  Future<DailyUsage> read(LocalDate day) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _inner.read(day);
  }

  @override
  Stream<DailyUsage> watchToday(LocalDate today) => _inner.watchToday(today);

  @override
  Future<void> recordCapture(LocalDate day, {required int taskCount}) =>
      _inner.recordCapture(day, taskCount: taskCount);

  @override
  Future<void> prune(LocalDate today, {int keepDays = 90}) =>
      _inner.prune(today, keepDays: keepDays);
}
