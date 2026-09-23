import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/home_shell.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// A recogniser that hands its session back only when the test says so: what
/// a whisper session cancelled after Stop does while it finishes the final
/// pass it cannot be interrupted in.
final class _SlowToLetGo implements SpeechRecognizer {
  final FakeSpeechRecognizer _inner = FakeSpeechRecognizer();
  Completer<void>? finalPass;

  @override
  Future<void> prepare() => _inner.prepare();

  @override
  Future<SpeechAvailability> availability() => _inner.availability();

  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) =>
      _inner.transcribeStream(pcm16);

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> cancel() async {
    final Completer<void>? gate = finalPass;
    finalPass = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> release() => _inner.release();
}

/// How the shell's mic button gets the user into the capture flow.
void main() {
  // ⚠️ A capture cancelled after Stop lets go of the speech model only once
  // whisper's final pass is done, which on a slow phone is many seconds. The
  // shell navigated only once `begin` returned, so for all of that wait the
  // mic tap looked like it had done nothing.
  //
  // Every `begin` here ends before a microphone opens, on purpose: at the
  // paywall (today's capture spent), or at a refused microphone past the
  // wait. The wait is the part under test, and a real recording under
  // FakeAsync deadlocks on its stream teardown (see redirect_test.dart
  // group 4).
  group('a mic tap that has to wait for the last capture', () {
    final DateTime now = DateTime(2026, 9, 21, 10, 30);

    late _SlowToLetGo recognizer;
    late ProviderContainer container;
    late GoRouter router;
    late List<String> redirected;

    String locationOf(GoRouter router) => router.state.matchedLocation;

    /// [spent] true: today's free captures are used up, so `begin` ends at
    /// the quota check. False: one is left, so `begin` waits for the last
    /// capture and then ends at a refused microphone.
    Future<void> pumpApp(WidgetTester tester, {bool spent = true}) async {
      await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      recognizer = _SlowToLetGo();
      final FakeUsageRepository usage = FakeUsageRepository();
      addTearDown(usage.dispose);
      if (spent) {
        for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
          await usage.recordCapture(LocalDate.today(now), taskCount: 1);
        }
      }

      container = ProviderContainer(
        overrides: <Override>[
          ...defaultOverrides(clock: FixedClock(now)),
          voiceCapturePipelineProvider.overrideWithValue(
            VoiceCapturePipeline(
              recorder: FakeAudioRecorder(),
              recognizer: recognizer,
              primaryExtractor: FakeTaskExtractor(),
              fallbackExtractor: FakeTaskExtractor(),
              permissions: FakePermissionService(
                states: <AppPermission, PermissionState>{
                  AppPermission.microphone: spent
                      ? PermissionState.granted
                      : PermissionState.permanentlyDenied,
                },
              ),
              usage: usage,
              clock: FixedClock(now),
              newDraftId: () => 'draft',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The app's capture rule, stated the same way: the phase decides which
      // capture screen is up, and an idle phase sends /capture Home.
      final ValueNotifier<CapturePhase> phase = ValueNotifier<CapturePhase>(
        CapturePhase.idle,
      );
      addTearDown(phase.dispose);
      container.listen<CapturePhase>(
        captureControllerProvider.select((CaptureState s) => s.phase),
        (CapturePhase? _, CapturePhase next) => phase.value = next,
      );
      redirected = <String>[];

      router = GoRouter(
        initialLocation: AppRoute.home.path,
        refreshListenable: phase,
        redirect: (BuildContext context, GoRouterState state) {
          final String location = state.matchedLocation;
          redirected.add(location);
          if (!location.startsWith(kCapturePathPrefix)) return null;
          final CapturePhase current = container
              .read(captureControllerProvider)
              .phase;
          if (current == CapturePhase.failed) return null;
          final String? allowed = captureLocationFor(current);
          if (allowed == null) return AppRoute.home.path;
          return location == allowed ? null : allowed;
        },
        routes: <RouteBase>[
          StatefulShellRoute.indexedStack(
            builder: (_, _, StatefulNavigationShell shell) =>
                HomeShell(navigationShell: shell),
            branches: <StatefulShellBranch>[
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: AppRoute.home.path,
                    builder: (_, _) => const Scaffold(body: Text('HOME')),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: AppRoute.capture.path,
            // The phase is what the real Recording screen reads to put
            // "Getting ready" up (see `_Recording.starting`).
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                    Text(
                      'CAPTURE '
                      '${ref.watch(captureControllerProvider).phase.name}',
                    ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoute.paywall.path,
            builder: (_, _) => const Scaffold(body: Text('PAYWALL')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: TasukeTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await pumpSettled(tester);
    }

    /// Unmounts inside the body, before the container is disposed under it.
    Future<void> shutdown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('puts the capture screen up for the wait, then the answer', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, spent: false);
      final Completer<void> finalPass = Completer<void>();
      recognizer.finalPass = finalPass;
      unawaited(container.read(captureControllerProvider.notifier).cancel());
      await tester.pump();

      await tester.tap(find.byType(MicFab));
      await tester.pump();
      await tester.pump();

      expect(locationOf(router), AppRoute.capture.path);
      expect(
        find.text('CAPTURE ${CapturePhase.checkingQuota.name}'),
        findsOneWidget,
        reason: 'the wait is on screen as "Getting ready", with a Cancel',
      );

      finalPass.complete();
      await pumpSettled(tester);

      // ⚠️ The shell that took the tap is gone by now; the answer still has
      // to land, through the router it held rather than its context.
      expect(locationOf(router), AppRoute.capture.path);
      expect(find.text('CAPTURE ${CapturePhase.failed.name}'), findsOneWidget);

      await shutdown(tester);
    });

    testWidgets('a spent quota goes straight to the paywall, saying why, even '
        'while the last capture is closing', (WidgetTester tester) async {
      // ⚠️ The quota is checked before the wait. A user who has used the
      // day's capture is not shown "Getting ready" for a microphone they
      // cannot use: before, they sat through the whole final pass for it.
      await pumpApp(tester);
      final Completer<void> finalPass = Completer<void>();
      recognizer.finalPass = finalPass;
      unawaited(container.read(captureControllerProvider.notifier).cancel());
      await tester.pump();

      await tester.tap(find.byType(MicFab));
      await pumpSettled(tester);

      expect(find.text('PAYWALL'), findsOneWidget);
      expect(locationOf(router), AppRoute.paywall.path);
      expect(
        router.state.uri.queryParameters['reason'],
        PaywallReason.quota.name,
      );
      expect(
        redirected,
        isNot(contains(AppRoute.capture.path)),
        reason: 'no capture screen flashed up on the way',
      );

      router.pop();
      await pumpSettled(tester);
      expect(find.text('HOME'), findsOneWidget);

      finalPass.complete();
      await pumpSettled(tester);
      await shutdown(tester);
    });

    testWidgets('a tap with nothing to wait for goes straight to the answer', (
      WidgetTester tester,
    ) async {
      // The early /capture is for the wait only. Without one the answer comes
      // back at once, and a capture screen flashed up under the paywall would
      // be noise.
      await pumpApp(tester);

      await tester.tap(find.byType(MicFab));
      await pumpSettled(tester);

      expect(find.text('PAYWALL'), findsOneWidget);
      expect(redirected, isNot(contains(AppRoute.capture.path)));

      await shutdown(tester);
    });
  });
}
