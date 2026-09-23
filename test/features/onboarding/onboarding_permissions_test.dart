import 'dart:async';

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
import 'package:tasuke_ai/features/onboarding/presentation/widgets/onboarding_illustration.dart';
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

    testWidgets('each page carries its own picture', (
      WidgetTester tester,
    ) async {
      // ⚠️ The bug this replaces shipped. All three pages drew the same
      // blurred brand orb with a brand-blue Material glyph on top of it —
      // blue on blue — so on a real phone the glyph was invisible and the
      // three pages were indistinguishable smudges. Asserting the picture
      // *changes* is what catches that coming back; asserting one exists is
      // not, because the broken version had one too.
      await pumpFirstRun(tester, at: AppRoute.onboarding.path);

      String currentArt() => tester
          .widget<OnboardingIllustration>(
            find.byType(OnboardingIllustration).first,
          )
          .asset;

      expect(currentArt(), TasukeArt.guideVoice);

      await swipeForward(tester);
      expect(currentArt(), TasukeArt.guideTasks);

      await swipeForward(tester);
      expect(currentArt(), TasukeArt.guidePrivacy);

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

  testWidgets('every onboarding page fits the smallest phone at 2× type', (
    WidgetTester tester,
  ) async {
    // ⚠️ The pages were plain Columns: at large type the body ran past the
    // pager and was clipped, with no way to scroll it back.
    await pumpScreen(
      tester,
      const OnboardingScreen(),
      overrides: defaultOverrides(
        permissions: permissions,
        preferences: preferences,
      ),
      frame: DeviceFrame.smallNoInsets,
      textScale: 2,
    );

    for (int page = 0; page < 3; page++) {
      expect(tester.takeException(), isNull, reason: 'page ${page + 1}');
      if (page < 2) {
        await tester.tap(find.text('Next'));
        await pumpSettled(tester);
      }
    }

    // The privacy promise, the last line of the last page, can be scrolled
    // into the pager rather than sitting clipped below it.
    final Finder promise = find.text(
      'Speech recognition and AI both run on this device. Your voice and '
      'your tasks never leave it.',
    );
    final Finder pageScroll = find.byWidgetPredicate(
      (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.drag(pageScroll, const Offset(0, -2000));
    await pumpSettled(tester);
    expect(
      tester.getBottomLeft(promise).dy,
      lessThanOrEqualTo(tester.getBottomLeft(find.byType(PageView)).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('permissions primer', () {
    testWidgets('asks for nothing on its own', (WidgetTester tester) async {
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text("Let's Get Started"), findsOneWidget);
      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Alarms & reminders'), findsOneWidget);
      // A prompt the user did not ask for is the one prompt iOS will not show
      // again. The primer explains first and asks on a tap.
      expect(permissions.requested, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the exact-alarm card is Android only', (
      WidgetTester tester,
    ) async {
      // iOS reports notApplicable. A card there would say "Allowed" about a
      // permission the user was never asked for.
      permissions.set(AppPermission.exactAlarm, PermissionState.notApplicable);
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text('Alarms & reminders'), findsNothing);
      expect(find.text('Allow'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a card asks the OS, and reports the answer it got', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.notDetermined,
          AppPermission.notifications: PermissionState.notDetermined,
        },
        grantOnRequest: true,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);
      expect(find.text('Allow'), findsNWidgets(3));

      await tester.tap(find.text('Microphone'));
      await pumpSettled(tester);

      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Allow'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the exact-alarm card opens its settings page', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.notDetermined,
          AppPermission.notifications: PermissionState.notDetermined,
          AppPermission.exactAlarm: PermissionState.denied,
        },
        grantOnRequest: true,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      await tester.tap(find.text('Alarms & reminders'));
      await pumpSettled(tester);

      // Android has no dialog for this one: `request` is what opens the
      // "Alarms & reminders" page.
      expect(permissions.requested, <AppPermission>[AppPermission.exactAlarm]);
      expect(find.text('Allowed'), findsOneWidget);

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

    testWidgets('Android: a silent refusal turns the card into Open Settings', (
      WidgetTester tester,
    ) async {
      // Android's status check says plain `denied` even after "never ask
      // again"; only the request's answer reveals it, with no dialog shown.
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.denied,
          AppPermission.notifications: PermissionState.granted,
          AppPermission.exactAlarm: PermissionState.granted,
        },
        answers: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.permanentlyDenied,
        },
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);
      expect(find.text('Allow'), findsOneWidget);

      await tester.tap(find.text('Microphone'));
      await pumpSettled(tester);

      // Visible feedback, and not a forced trip out of the app.
      expect(find.text('Open Settings'), findsOneWidget);
      expect(permissions.settingsOpened, 0);

      await tester.tap(find.text('Microphone'));
      await pumpSettled(tester);
      expect(permissions.settingsOpened, 1);
      expect(permissions.requested, <AppPermission>[AppPermission.microphone]);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Allow all asks for each one in order, then moves on', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.notDetermined,
          AppPermission.notifications: PermissionState.notDetermined,
          AppPermission.exactAlarm: PermissionState.denied,
        },
        grantOnRequest: true,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      await tester.tap(find.text('Allow all'));
      await pumpSettled(tester);

      // Microphone first, exact alarms last: the dependency order.
      expect(permissions.requested, <AppPermission>[
        AppPermission.microphone,
        AppPermission.notifications,
        AppPermission.exactAlarm,
      ]);
      expect(find.text('Home'), findsOneWidget);
      expect(preferences.getBool(PrefKeys.permissionsPrimerSeen), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Allow all skips what is already granted', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.granted,
          AppPermission.notifications: PermissionState.notDetermined,
          AppPermission.exactAlarm: PermissionState.granted,
        },
        grantOnRequest: true,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      await tester.tap(find.text('Allow all'));
      await pumpSettled(tester);

      expect(permissions.requested, <AppPermission>[
        AppPermission.notifications,
      ]);
      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Allow all stays put while something is still refused', (
      WidgetTester tester,
    ) async {
      // Every prompt answered "Don't Allow".
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      await tester.tap(find.text('Allow all'));
      await pumpSettled(tester);

      expect(permissions.requested, hasLength(3));
      expect(find.byType(PermissionsScreen), findsOneWidget);
      expect(find.text('Allow all'), findsOneWidget);
      expect(preferences.getBool(PrefKeys.permissionsPrimerSeen), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Allow all sends permanent denials to Settings, once', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.permanentlyDenied,
          AppPermission.notifications: PermissionState.permanentlyDenied,
          AppPermission.exactAlarm: PermissionState.denied,
        },
        grantOnRequest: true,
      );
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      await tester.tap(find.text('Allow all'));
      await pumpSettled(tester);

      // One trip out of the app, not one per permission.
      expect(permissions.settingsOpened, 1);
      expect(permissions.requested, <AppPermission>[AppPermission.exactAlarm]);
      expect(find.byType(PermissionsScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Not now works with nothing granted — a primer, not a gate', (
      WidgetTester tester,
    ) async {
      permissions
        ..set(AppPermission.microphone, PermissionState.permanentlyDenied)
        ..set(AppPermission.notifications, PermissionState.denied);
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      // ⚠️ A blocked way forward would be a dead end the app cannot escape:
      // iOS never prompts twice. The Home banner is what keeps nagging.
      await tester.tap(find.text('Not now'));
      await pumpSettled(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(PermissionsScreen), findsNothing);
      expect(preferences.getBool(PrefKeys.permissionsPrimerSeen), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with everything granted the button is just Continue', (
      WidgetTester tester,
    ) async {
      permissions
        ..set(AppPermission.microphone, PermissionState.granted)
        ..set(AppPermission.notifications, PermissionState.granted)
        ..set(AppPermission.exactAlarm, PermissionState.granted);
      await pumpFirstRun(tester, at: AppRoute.permissions.path);

      expect(find.text('Allowed'), findsNWidgets(3));
      expect(find.text('Not now'), findsNothing);

      await tester.tap(find.text('Continue'));
      await pumpSettled(tester);

      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('three cards fit the smallest phone at 2× type', (
    WidgetTester tester,
  ) async {
    // Three cards, a two-line title and two buttons do not fit 320×568 at 2×.
    // The screen scrolls instead of painting an overflow stripe.
    for (final bool fixing in <bool>[false, true]) {
      await pumpScreen(
        tester,
        PermissionsScreen(fixing: fixing),
        overrides: defaultOverrides(
          permissions: permissions,
          preferences: preferences,
        ),
        frame: DeviceFrame.smallNoInsets,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alarms & reminders'), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('fixing from Home', () {
    /// Home pushes `/access`; the screen must pop back to it.
    Future<GoRouter> pumpFix(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final GoRouter router = GoRouter(
        initialLocation: AppRoute.home.path,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.home.path,
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('Home'))),
          ),
          GoRoute(
            path: AppRoute.access.path,
            builder: (_, _) => const PermissionsScreen(fixing: true),
          ),
        ],
      );
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
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push<void>(AppRoute.access.path));
      await pumpSettled(tester);
      return router;
    }

    testWidgets('says what is wrong and pops back once it is fixed', (
      WidgetTester tester,
    ) async {
      permissions = FakePermissionService(
        states: <AppPermission, PermissionState>{
          AppPermission.microphone: PermissionState.denied,
          AppPermission.notifications: PermissionState.denied,
          AppPermission.exactAlarm: PermissionState.granted,
        },
        grantOnRequest: true,
      );
      await pumpFix(tester);

      expect(find.text('Turn On Permissions'), findsOneWidget);

      await tester.tap(find.text('Allow all'));
      await pumpSettled(tester);

      expect(find.byType(PermissionsScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      // The first-run flag belongs to first run.
      expect(preferences.getBool(PrefKeys.permissionsPrimerSeen), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Not now pops back too', (WidgetTester tester) async {
      await pumpFix(tester);

      await tester.tap(find.text('Not now'));
      await pumpSettled(tester);

      expect(find.byType(PermissionsScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
