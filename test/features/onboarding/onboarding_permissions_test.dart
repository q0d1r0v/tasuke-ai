import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tasuke_ai/features/permissions/presentation/permissions_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The two screens a first launch is made of.
///
/// Both are one-way doors that latch a `SharedPreferences` flag, so the thing
/// worth testing is not that they draw — it is that they let the user through
/// and remember that they did.
void main() {
  late FakePermissionService permissions;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    // Nothing answered yet: the state a real first launch is in.
    permissions = FakePermissionService(
      states: <AppPermission, PermissionState>{
        AppPermission.microphone: PermissionState.notDetermined,
        AppPermission.notifications: PermissionState.notDetermined,
      },
    );
  });

  /// Pumps the first-run routes over a real [GoRouter].
  ///
  /// Both screens navigate with `context.go`, so a bare `MaterialApp` home is
  /// not enough: the assertion that matters is which screen the tap lands on.
  Future<void> pumpFirstRun(WidgetTester tester, {required String at}) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            permissions: permissions,
            preferences: preferences,
          ),
        ],
        child: MaterialApp.router(
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: at,
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.onboarding.path,
                builder: (_, _) => const OnboardingScreen(),
              ),
              GoRoute(
                path: AppRoute.permissions.path,
                builder: (_, _) => const PermissionsScreen(),
              ),
              // A stand-in for the shell: what matters here is only that the
              // app got past the first-run screens.
              GoRoute(
                path: AppRoute.home.path,
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Home'))),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpSettled(tester);
  }

  /// One full page-width swipe. The pager is 375pt wide in this frame.
  Future<void> swipeForward(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await pumpSettled(tester);
  }

  int dotIndex(WidgetTester tester) =>
      tester.widget<PageDots>(find.byType(PageDots)).index;

  group('onboarding', () {
    testWidgets('opens on the first of three pages', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      expect(find.text('Turn Your Voice into Action'), findsOneWidget);
      expect(tester.widget<PageDots>(find.byType(PageDots)).count, 3);
      expect(dotIndex(tester), 0);
      // "Next" while there is a next page, so the CTA never promises to finish
      // something it is only going to advance.
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the dots track the pager and the last page says Continue', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      await swipeForward(tester);
      expect(find.text('One Sentence, Many Tasks'), findsOneWidget);
      expect(dotIndex(tester), 1);
      expect(find.text('Next'), findsOneWidget);

      await swipeForward(tester);
      expect(find.text('Private by Design'), findsOneWidget);
      expect(dotIndex(tester), 2);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Next'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Next walks the pager rather than skipping to the end', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      await tester.tap(find.text('Next'));
      await pumpSettled(tester);

      expect(dotIndex(tester), 1);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Skip jumps to the primer and latches the seen flag', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      await tester.tap(find.text('Skip'));
      await pumpSettled(tester);

      expect(find.byType(PermissionsScreen), findsOneWidget);
      // ⚠️ Latched, not merely navigated past. The router's guard reads this
      // flag on the very frame the tap navigates, so a user who skips must not
      // be sent back here on the next cold start.
      expect(preferences.getBool(PrefKeys.onboardingSeen), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Continue on the last page routes on to the primer', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      await swipeForward(tester);
      await swipeForward(tester);
      await tester.tap(find.text('Continue'));
      await pumpSettled(tester);

      expect(find.byType(PermissionsScreen), findsOneWidget);
      expect(preferences.getBool(PrefKeys.onboardingSeen), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('permissions primer', () {
    testWidgets('asks for nothing on its own', (WidgetTester tester) async {
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text("Let's Get Started"), findsOneWidget);
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // A prompt the user did not ask for is the one prompt iOS will not show
      // again. The primer explains first and asks on a tap.
      expect(permissions.requested, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a card asks the OS, and reports the answer it got', (
      WidgetTester tester,
    ) async {
      await pumpFirstRun(tester, at: AppRoute.permissions.path);
      expect(find.text('Allow'), findsNWidgets(2));

      permissions.set(AppPermission.microphone, PermissionState.granted);
      await tester.tap(find.text('Microphone'));
      await pumpSettled(tester);

      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a permanent denial swaps the action to Open Settings', (
      WidgetTester tester,
    ) async {
      permissions.set(
        AppPermission.notifications,
        PermissionState.permanentlyDenied,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.text('Notifications'));
      await pumpSettled(tester);

      // ⚠️ Re-requesting a permanently denied permission silently no-ops, and
      // a button that does nothing reads as a broken app.
      expect(permissions.settingsOpened, 1);
      expect(
        permissions.requested,
        isNot(contains(AppPermission.notifications)),
      );
      expect(find.text('Open Settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Continue works with nothing granted — a primer, not a gate', (
      WidgetTester tester,
    ) async {
      permissions
        ..set(AppPermission.microphone, PermissionState.permanentlyDenied)
        ..set(AppPermission.notifications, PermissionState.denied);
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      // ⚠️ A blocked Continue would be a dead end the app cannot escape: iOS
      // never prompts twice, so the button could never become enabled.
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Continue'));
      await pumpSettled(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(PermissionsScreen), findsNothing);
      expect(preferences.getBool(PrefKeys.permissionsPrimerSeen), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Continue works with everything granted too', (
      WidgetTester tester,
    ) async {
      permissions
        ..set(AppPermission.microphone, PermissionState.granted)
        ..set(AppPermission.notifications, PermissionState.granted);
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text('Allowed'), findsNWidgets(2));

      await tester.tap(find.text('Continue'));
      await pumpSettled(tester);

      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
