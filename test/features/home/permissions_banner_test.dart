import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The Home warning that stays up while a required permission is off.
///
/// ⚠️ It is the only thing that makes the permissions non-optional — the
/// primer has a "Not now" on purpose — so a regression here is silent: the
/// app just quietly stops ringing or listening, with nothing on screen to say
/// why. That is exactly how a 6:11 PM reminder went missing on a real phone.
void main() {
  const String micOff =
      "The microphone is off, so voice capture won't work. Tap to allow it.";
  const String notificationsOff =
      "Notifications are off, so reminders won't ring. Tap to turn them on.";
  const String exactOff =
      'Reminders may arrive up to an hour late. Tap to fix.';
  const String severalOff =
      "Some permissions are off, so voice capture or reminders won't work. "
      'Tap to fix.';

  late FakeTaskRepository tasks;

  setUp(() => tasks = FakeTaskRepository());
  tearDown(() => tasks.dispose());

  FakePermissionService only(
    Map<AppPermission, PermissionState> changes, {
    bool grantOnRequest = false,
  }) => FakePermissionService(
    states: <AppPermission, PermissionState>{
      AppPermission.microphone: PermissionState.granted,
      AppPermission.notifications: PermissionState.granted,
      AppPermission.exactAlarm: PermissionState.granted,
      ...changes,
    },
    grantOnRequest: grantOnRequest,
  );

  Future<void> pumpHome(
    WidgetTester tester,
    FakePermissionService permissions,
  ) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            clock: FixedClock(DateTime(2026, 3, 11, 10)),
            permissions: permissions,
          ),
          taskRepositoryProvider.overrideWithValue(tasks),
        ],
        child: MaterialApp.router(
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: AppRoute.home.path,
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.home.path,
                builder: (_, _) => const Scaffold(body: HomeScreen()),
              ),
              GoRoute(
                path: AppRoute.access.path,
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('access'))),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpSettled(tester);
  }

  /// Unmounted at the END of the body: flutter_test checks for pending timers
  /// before teardown callbacks run.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('nothing missing, nothing shown', (WidgetTester tester) async {
    await pumpHome(tester, only(const <AppPermission, PermissionState>{}));

    for (final String text in <String>[
      micOff,
      notificationsOff,
      exactOff,
      severalOff,
    ]) {
      expect(find.text(text), findsNothing);
    }

    await shutdown(tester);
  });

  testWidgets('a missing microphone is named, and one tap asks for it', (
    WidgetTester tester,
  ) async {
    final FakePermissionService permissions = only(
      const <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.denied,
      },
      grantOnRequest: true,
    );
    await pumpHome(tester, permissions);

    expect(find.text(micOff), findsOneWidget);

    await tester.tap(find.text(micOff));
    await pumpSettled(tester);

    expect(permissions.requested, <AppPermission>[AppPermission.microphone]);
    // Granted, so the warning is gone without leaving Home.
    expect(find.text(micOff), findsNothing);

    await shutdown(tester);
  });

  testWidgets('notifications refused for good go to Settings, not a prompt', (
    WidgetTester tester,
  ) async {
    final FakePermissionService permissions = only(
      const <AppPermission, PermissionState>{
        AppPermission.notifications: PermissionState.permanentlyDenied,
      },
    );
    await pumpHome(tester, permissions);

    expect(find.text(notificationsOff), findsOneWidget);

    await tester.tap(find.text(notificationsOff));
    await pumpSettled(tester);

    // ⚠️ A re-request would silently no-op: the tap would do nothing at all.
    expect(permissions.settingsOpened, 1);
    expect(permissions.requested, isEmpty);

    await shutdown(tester);
  });

  testWidgets('a refusal with no dialog still leads somewhere visible', (
    WidgetTester tester,
  ) async {
    // Android: the status check said plain `denied`, the request came back
    // "never ask again" with no dialog at all. The tap used to do nothing.
    final FakePermissionService permissions = FakePermissionService(
      states: <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.denied,
        AppPermission.notifications: PermissionState.granted,
        AppPermission.exactAlarm: PermissionState.granted,
      },
      answers: <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.permanentlyDenied,
      },
    );
    await pumpHome(tester, permissions);

    await tester.tap(find.text(micOff));
    await pumpSettled(tester);

    // Offered, not forced.
    expect(permissions.settingsOpened, 0);
    expect(
      find.text("Your phone won't ask again. Turn it on in Settings."),
      findsOneWidget,
    );

    await tester.tap(find.text('Open Settings'));
    await pumpSettled(tester);
    expect(permissions.settingsOpened, 1);

    // And the next tap on the warning goes straight there.
    await tester.tap(find.text(micOff));
    await pumpSettled(tester);
    expect(permissions.settingsOpened, 2);
    expect(permissions.requested, <AppPermission>[AppPermission.microphone]);

    await shutdown(tester);
  });

  testWidgets('exact alarms off: warned, and the tap opens its page', (
    WidgetTester tester,
  ) async {
    final FakePermissionService permissions = only(
      const <AppPermission, PermissionState>{
        AppPermission.exactAlarm: PermissionState.denied,
      },
    );
    await pumpHome(tester, permissions);

    expect(find.text(exactOff), findsOneWidget);

    await tester.tap(find.text(exactOff));
    await pumpSettled(tester);

    expect(permissions.requested, <AppPermission>[AppPermission.exactAlarm]);

    await shutdown(tester);
  });

  testWidgets('nothing the user cannot fix is warned about', (
    WidgetTester tester,
  ) async {
    // restricted: a device policy. notApplicable: iOS has no exact alarms.
    await pumpHome(
      tester,
      only(const <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.restricted,
        AppPermission.exactAlarm: PermissionState.notApplicable,
      }),
    );

    expect(find.text(micOff), findsNothing);
    expect(find.text(exactOff), findsNothing);
    expect(find.text(severalOff), findsNothing);

    await shutdown(tester);
  });

  testWidgets('several missing: one warning, and it opens the fix screen', (
    WidgetTester tester,
  ) async {
    final FakePermissionService permissions = only(
      const <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.denied,
        AppPermission.notifications: PermissionState.denied,
      },
    );
    await pumpHome(tester, permissions);

    expect(find.text(severalOff), findsOneWidget);
    expect(find.text(micOff), findsNothing);

    await tester.tap(find.text(severalOff));
    await pumpSettled(tester);

    expect(find.text('access'), findsOneWidget);
    // The fix screen asks; the banner itself does not fire three prompts.
    expect(permissions.requested, isEmpty);

    await shutdown(tester);
  });

  testWidgets('a fix made in the Settings app clears it on the next check', (
    WidgetTester tester,
  ) async {
    final FakePermissionService permissions = only(
      const <AppPermission, PermissionState>{
        AppPermission.notifications: PermissionState.permanentlyDenied,
      },
    );
    await pumpHome(tester, permissions);
    expect(find.text(notificationsOff), findsOneWidget);

    // The user flips the switch in Settings and comes back: AppLifecycleHost
    // invalidates every permission status on resume.
    permissions.set(AppPermission.notifications, PermissionState.granted);
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .invalidate(permissionStatusProvider);
    await pumpSettled(tester);

    expect(find.text(notificationsOff), findsNothing);

    await shutdown(tester);
  });
}
