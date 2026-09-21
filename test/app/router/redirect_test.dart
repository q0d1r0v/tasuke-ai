import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/app.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/router/app_router.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/confirm/presentation/confirm_tasks_screen.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/model_setup/presentation/model_setup_screen.dart';
import 'package:tasuke_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tasuke_ai/features/permissions/presentation/permissions_screen.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/splash/presentation/splash_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// A latch a test never opens.
///
/// ⚠️ Three capture phases exist only while something asynchronous is in
/// flight. The only way to stand in one and read the router is to hold the port
/// that phase is waiting on — and to hold it for good: letting the pipeline
/// through would open the microphone, and closing a microphone stream is the
/// one thing a test body may not await (see the note in group 5).
final class Gate {
  final Completer<void> _completer = Completer<void>();

  Future<void> get opened => _completer.future;
}

/// Holds `checkQuota`, the first thing the mic button does.
///
/// [armed] only after boot: the app reads usage on its way up, and a gate
/// closed too early strands the whole launch on the splash.
final class GatedUsage implements UsageRepository {
  GatedUsage(this._inner);

  final FakeUsageRepository _inner;
  final Gate gate = Gate();
  bool armed = false;

  @override
  Future<DailyUsage> read(LocalDate day) async {
    if (armed) await gate.opened;
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

/// Holds the microphone prompt.
final class GatedPermissions implements PermissionService {
  final Gate gate = Gate();
  bool armed = false;

  @override
  Future<PermissionState> status(AppPermission permission) async {
    if (armed && permission == AppPermission.microphone) await gate.opened;
    return PermissionState.granted;
  }

  @override
  Future<PermissionState> request(AppPermission permission) async =>
      PermissionState.granted;

  @override
  Future<bool> openSettings() async => true;
}

/// Holds the settings read that `save()` opens with.
///
/// ⚠️ [armed] after boot for the same reason as [GatedUsage]: the bootstrap's
/// reminder sweep reads settings too, and blocking it never lets the app start.
final class GatedSettings implements SettingsRepository {
  GatedSettings(this._inner);

  final FakeSettingsRepository _inner;
  final Gate gate = Gate();
  bool armed = false;

  @override
  Future<AppSettings> read() async {
    if (armed) await gate.opened;
    return _inner.read();
  }

  @override
  Stream<AppSettings> watch() => _inner.watch();

  @override
  Future<void> write(AppSettings settings) => _inner.write(settings);
}

void main() {
  /// Wednesday 11 March 2026, 10:00 local.
  final DateTime testNow = DateTime(2026, 3, 11, 10);

  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late FakeLocalNotifier notifier;
  late FakeAudioRecorder recorder;
  late FakeSpeechRecognizer speech;
  late MutableClock clock;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    notifier = FakeLocalNotifier();
    recorder = FakeAudioRecorder();
    speech = FakeSpeechRecognizer(transcript: 'call mum tomorrow');
    clock = MutableClock(testNow);
  });

  // ⚠️ Closed here rather than inside the test body: awaiting a stream close
  // inside `FakeAsync` is a deadlock no test timeout can interrupt.
  tearDown(() {
    notifier.dispose();
    tasks.dispose();
    settings.dispose();
    usage.dispose();
  });

  /// Boots the real app, with the real router, over fakes.
  Future<GoRouter> bootApp(
    WidgetTester tester, {
    bool onboardingSeen = true,
    bool primerSeen = true,
    bool bootstrapPending = false,
    ModelState model = const ModelNotInstalled(),
    UsageRepository? usageRepository,
    PermissionService? permissions,
    SpeechRecognizer? recognizer,
    TaskExtractor? extractor,
    SettingsRepository? settingsRepository,
  }) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    if (onboardingSeen) {
      await preferences.setBool(PrefKeys.onboardingSeen, true);
    }
    if (primerSeen) {
      await preferences.setBool(PrefKeys.permissionsPrimerSeen, true);
    }

    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final FakeModelInstaller installer = FakeModelInstaller(initial: model);
    addTearDown(installer.dispose);
    final FakePurchaseGateway purchases = FakePurchaseGateway();
    addTearDown(purchases.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clockProvider.overrideWithValue(clock),
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioRecorderProvider.overrideWithValue(recorder),
          speechRecognizerProvider.overrideWithValue(recognizer ?? speech),
          permissionServiceProvider.overrideWithValue(
            permissions ?? FakePermissionService(),
          ),
          localNotifierProvider.overrideWithValue(notifier),
          purchaseGatewayProvider.overrideWithValue(purchases),
          modelInstallerProvider.overrideWithValue(installer),
          // ⚠️ The bootstrap opens the real database to surface a corrupt file
          // on the splash. In a widget test that is a deadlock, not a check.
          databaseHealthProvider.overrideWith((Ref ref) async {}),
          if (bootstrapPending)
            appBootstrapProvider.overrideWith(
              (Ref ref) => Completer<BootstrapResult>().future,
            ),
          taskRepositoryProvider.overrideWithValue(tasks),
          settingsRepositoryProvider.overrideWithValue(
            settingsRepository ?? settings,
          ),
          usageRepositoryProvider.overrideWithValue(usageRepository ?? usage),
          if (extractor != null)
            primaryTaskExtractorProvider.overrideWithValue(extractor),
          if (extractor != null)
            fallbackTaskExtractorProvider.overrideWithValue(extractor),
        ],
        child: const TasukeApp(),
      ),
    );
    await pumpSettled(tester);

    return ProviderScope.containerOf(
      tester.element(find.byType(TasukeApp)),
      listen: false,
    ).read(routerProvider);
  }

  String locationOf(GoRouter router) => router.state.matchedLocation;

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(TasukeApp)),
        listen: false,
      );

  CaptureController controllerOf(WidgetTester tester) =>
      containerOf(tester).read(captureControllerProvider.notifier);

  CaptureState stateOf(WidgetTester tester) =>
      containerOf(tester).read(captureControllerProvider);

  /// Unmounts the tree **inside the test body**.
  ///
  /// ⚠️ Not `addTearDown`: flutter_test asserts on pending timers at the end of
  /// the body, which runs before any teardown callback.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('1. the bootstrap gate', () {
    testWidgets('holds everything on the splash until the database answers', (
      WidgetTester tester,
    ) async {
      // Everything below this gate needs the database and the notifier, so a
      // pending bootstrap is the one case where the splash is not a delay but
      // an answer.
      final GoRouter router = await bootApp(tester, bootstrapPending: true);

      expect(locationOf(router), AppRoute.splash.path);
      expect(find.byType(SplashScreen), findsOneWidget);

      router.go(AppRoute.home.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.splash.path);
      await shutdown(tester);
    });

    testWidgets('lets go of the splash the moment the bootstrap lands', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(tester);

      expect(locationOf(router), AppRoute.home.path);
      expect(find.byType(SplashScreen), findsNothing);
      await shutdown(tester);
    });
  });

  group('2. first run', () {
    testWidgets('a user who has not seen onboarding cannot leave it', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(
        tester,
        onboardingSeen: false,
        primerSeen: false,
      );

      expect(locationOf(router), AppRoute.onboarding.path);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      router.go(AppRoute.home.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.onboarding.path);
      await shutdown(tester);
    });
  });

  group('3. the permissions primer', () {
    testWidgets('comes after onboarding and before Home', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(tester, primerSeen: false);

      expect(locationOf(router), AppRoute.permissions.path);
      expect(find.byType(PermissionsScreen), findsOneWidget);

      router.go(AppRoute.settings.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.permissions.path);
      await shutdown(tester);
    });

    testWidgets('is a primer, not a gate: no OS grant is required', (
      WidgetTester tester,
    ) async {
      // ⚠️ If this blocked on the grant, a user who tapped "Don't Allow" would
      // be in a dead end the app could not escape — iOS never re-prompts, so
      // Continue could never become enabled.
      final GoRouter router = await bootApp(
        tester,
        primerSeen: false,
        permissions: FakePermissionService(
          states: <AppPermission, PermissionState>{
            AppPermission.microphone: PermissionState.permanentlyDenied,
            AppPermission.notifications: PermissionState.denied,
          },
        ),
      );

      expect(locationOf(router), AppRoute.permissions.path);
      await shutdown(tester);
    });
  });

  group('4. model setup', () {
    testWidgets('is offered while the model is missing', (
      WidgetTester tester,
    ) async {
      // Not a gate: the app is fully usable — manual tasks, reminders, every
      // screen — while the 219 MB download runs.
      final GoRouter router = await bootApp(tester);

      router.go(AppRoute.modelSetup.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.modelSetup.path);
      expect(find.byType(ModelSetupScreen), findsOneWidget);
      await shutdown(tester);
    });

    testWidgets('stays reachable once the model is ready', (
      WidgetTester tester,
    ) async {
      // ⚠️ The guard deliberately does NOT bounce a ready model off this
      // screen. `/model-setup` is shown once during first run and reached
      // from Settings → AI model at any time afterwards; bouncing would mean a
      // user who tapped "Not now" could never enable voice capture at all,
      // and the review notes promise that row works. The screen itself decides
      // what to render for the current state.
      final GoRouter router = await bootApp(
        tester,
        model: const ModelReady('/tmp/extractor.gguf'),
      );

      router.go(AppRoute.modelSetup.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.modelSetup.path);
      expect(find.byType(ModelSetupScreen), findsOneWidget);
      await shutdown(tester);
    });
  });

  group('5. the capture family', () {
    // ⚠️ This group deliberately tests the phase→location TABLE directly, and
    // drives the router only for the one case that needs no suspended
    // pipeline.
    //
    // The obvious version — hold `begin()` inside a gated repository, drive the
    // router, then cancel — deadlocks the isolate inside `FakeAsync`. Tearing
    // the capture down awaits a `StreamController.close()`, which completes
    // only once its listener has been given `onDone`; that is an EVENT, and
    // nothing in a test body delivers events. No test timeout interrupts it, so
    // it presents as a native hang rather than as a failure, and it takes the
    // whole suite with it.
    //
    // What the table cannot prove — that the router really honours it end to
    // end — is covered by `test/flows/app_flows_test.dart`, which runs a real
    // capture through to a saved task.

    test('every phase maps to exactly the screen the design shows', () {
      expect(captureLocationFor(CapturePhase.idle), isNull);
      expect(
        captureLocationFor(CapturePhase.checkingQuota),
        AppRoute.capture.path,
      );
      expect(
        captureLocationFor(CapturePhase.requestingPermission),
        AppRoute.capture.path,
      );
      expect(captureLocationFor(CapturePhase.recording), AppRoute.capture.path);
      expect(
        captureLocationFor(CapturePhase.transcribing),
        AppRoute.captureProcessing.path,
      );
      expect(
        captureLocationFor(CapturePhase.extracting),
        AppRoute.captureProcessing.path,
      );
      expect(
        captureLocationFor(CapturePhase.confirming),
        AppRoute.captureConfirm.path,
      );
      expect(
        captureLocationFor(CapturePhase.saving),
        AppRoute.captureConfirm.path,
      );
    });

    test('a failure pins nothing, so the screen can render its own error', () {
      // The guard returns early for `failed`, leaving the user where the
      // failure happened rather than bouncing them to Home mid-message.
      expect(captureLocationFor(CapturePhase.failed), isNull);
    });

    test('the table covers every phase there is', () {
      // ⚠️ A new phase with no entry would fall through to `null` and silently
      // bounce the user to Home. The switch is exhaustive, so this is really a
      // reminder that adding a phase means adding a row above.
      for (final CapturePhase phase in CapturePhase.values) {
        expect(
          () => captureLocationFor(phase),
          returnsNormally,
          reason: '$phase has no entry in the capture location table',
        );
      }
    });

    testWidgets('idle sends a cold-start deep link to Home', (
      WidgetTester tester,
    ) async {
      // ⚠️ A cold start into `/capture/confirm` — from a stale deep link or a
      // restored task stack — must land on Home, not on a confirm screen with
      // nothing to confirm.
      final GoRouter router = await bootApp(tester);

      router.go(AppRoute.captureConfirm.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.home.path);
      expect(find.byType(HomeScreen), findsOneWidget);
      await shutdown(tester);
    });

    testWidgets('checkingQuota holds the user on the recording screen', (
      WidgetTester tester,
    ) async {
      // The gate is never opened, and that is the point: blocked before the
      // microphone, the pipeline owns no stream and no ticker, so the phase can
      // be read through the real router without anything to tear down.
      final GatedUsage gated = GatedUsage(usage);
      final GoRouter router = await bootApp(tester, usageRepository: gated);
      gated.armed = true;

      unawaited(controllerOf(tester).begin());
      await pumpSettled(tester);
      router.go(AppRoute.captureConfirm.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.capture.path);
      expect(find.byType(RecordingScreen), findsOneWidget);
      await shutdown(tester);
    });

    testWidgets('requestingPermission holds the user on the same screen', (
      WidgetTester tester,
    ) async {
      final GatedPermissions gated = GatedPermissions();
      final GoRouter router = await bootApp(tester, permissions: gated);
      gated.armed = true;

      unawaited(controllerOf(tester).begin());
      await pumpSettled(tester);
      router.go(AppRoute.captureProcessing.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.capture.path);
      await shutdown(tester);
    });

    testWidgets('confirming pulls a stray recorder link to the cards', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(tester);
      controllerOf(tester).startManualDraft();
      await pumpSettled(tester);

      router.go(AppRoute.capture.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.captureConfirm.path);
      expect(find.byType(ConfirmTasksScreen), findsOneWidget);
      await shutdown(tester);
    });

    testWidgets('saving keeps the confirm screen up rather than navigating', (
      WidgetTester tester,
    ) async {
      // Save shows a spinner in place; a flow that navigated mid-write would
      // leave the user unable to see which cards were saved.
      final GatedSettings gated = GatedSettings(settings);
      final GoRouter router = await bootApp(tester, settingsRepository: gated);
      gated.armed = true;

      final CaptureController controller = controllerOf(tester);
      controller.startManualDraft();
      controller.updateDraft(
        stateOf(tester).drafts.single
            .copyWith(title: 'Send the build to James'),
      );
      unawaited(controller.save());
      await pumpSettled(tester);
      expect(stateOf(tester).phase, CapturePhase.saving);

      router.go(AppRoute.capture.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.captureConfirm.path);
      await shutdown(tester);
    });

    testWidgets(
      'a failure stays where it happened, for the screen to explain',
      (WidgetTester tester) async {
        // ⚠️ `begin()` is safe to await here precisely because a denied
        // microphone never opens one — there is no stream to close afterwards.
        final GoRouter router = await bootApp(
          tester,
          permissions: FakePermissionService(
            states: <AppPermission, PermissionState>{
              AppPermission.microphone: PermissionState.permanentlyDenied,
            },
          ),
        );

        await controllerOf(tester).begin();
        await pumpSettled(tester);
        expect(stateOf(tester).phase, CapturePhase.failed);

        router.go(AppRoute.capture.path);
        await pumpSettled(tester);

        expect(locationOf(router), AppRoute.capture.path);
        expect(find.byType(RecordingScreen), findsOneWidget);
        await shutdown(tester);
      },
    );
  });

  group('6. the transient screens', () {
    testWidgets('bounce a configured user straight to Home', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(tester);

      for (final String path in kTransientPaths) {
        // `/model-setup` has its own rule above; the other three are pure
        // "nobody who is set up belongs here".
        if (path == AppRoute.modelSetup.path) continue;
        router.go(path);
        await pumpSettled(tester);
        expect(
          locationOf(router),
          AppRoute.home.path,
          reason: '$path should bounce a configured user to Home',
        );
      }
      await shutdown(tester);
    });

    testWidgets('a real destination is left alone', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await bootApp(tester);

      router.go(AppRoute.settings.path);
      await pumpSettled(tester);

      expect(locationOf(router), AppRoute.settings.path);
      await shutdown(tester);
    });
  });
}
