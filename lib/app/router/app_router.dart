import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override`, `ProviderListenable` or the
// `*Family` types from its main library — only from `misc.dart`. Naming any of
// them without this import is a `non_type_as_type_argument` error that reads
// like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/router/home_shell.dart';
import 'package:tasuke_ai/app/router/router_refresh.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/capture/presentation/recording_screen.dart';
import 'package:tasuke_ai/features/confirm/presentation/confirm_tasks_screen.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tasuke_ai/features/permissions/presentation/permissions_screen.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/processing/presentation/processing_screen.dart';
import 'package:tasuke_ai/features/search/presentation/search_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/about_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/help_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/language_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/legal_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/settings_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/usage_screen.dart';
import 'package:tasuke_ai/features/splash/presentation/splash_screen.dart';
import 'package:tasuke_ai/features/stats/presentation/stats_screen.dart';
import 'package:tasuke_ai/features/subscription/presentation/paywall_screen.dart';
import 'package:tasuke_ai/features/task_detail/presentation/task_detail_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// The router.
///
/// Kept alive for the process: rebuilding it would drop the navigation stack.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final RouterRefreshNotifier refresh = RouterRefreshNotifier(
    ref,
    <ProviderListenable<Object?>>[
      appBootstrapProvider,
      onboardingSeenProvider,
      permissionsPrimerSeenProvider,
      captureControllerProvider.select((CaptureState state) => state.phase),
    ],
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoute.splash.path,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) =>
        _redirect(ref, state),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.routeName,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding.path,
        name: AppRoute.onboarding.routeName,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoute.permissions.path,
        name: AppRoute.permissions.routeName,
        builder: (_, _) => const PermissionsScreen(),
      ),
      GoRoute(
        path: AppRoute.access.path,
        name: AppRoute.access.routeName,
        builder: (_, _) => const PermissionsScreen(fixing: true),
      ),

      // The four bottom-nav destinations.
      //
      // `indexedStack` so each branch keeps its own Navigator and its own
      // scroll position: tapping Home while on Settings and coming back lands
      // the list exactly where it was, for free.
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell shell) =>
            HomeShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.home.path,
                name: AppRoute.home.routeName,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.search.path,
                name: AppRoute.search.routeName,
                builder: (_, _) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.stats.path,
                name: AppRoute.stats.routeName,
                builder: (_, _) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.settings.path,
                name: AppRoute.settings.routeName,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // The capture family sits ABOVE the shell, so the notched nav bar and its
      // mic button do not float over a recording screen.
      GoRoute(
        path: AppRoute.capture.path,
        name: AppRoute.capture.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const RecordingScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'processing',
            name: AppRoute.captureProcessing.routeName,
            parentNavigatorKey: _rootNavigatorKey,
            builder: (_, _) => const ProcessingScreen(),
          ),
          GoRoute(
            path: 'confirm',
            name: AppRoute.captureConfirm.routeName,
            parentNavigatorKey: _rootNavigatorKey,
            builder: (_, _) => const ConfirmTasksScreen(),
          ),
        ],
      ),

      GoRoute(
        path: AppRoute.taskDetail.path,
        name: AppRoute.taskDetail.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) =>
            TaskDetailScreen(taskId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoute.paywall.path,
        name: AppRoute.paywall.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, GoRouterState state) => PaywallScreen(
          reason: PaywallReason.fromQuery(state.uri.queryParameters),
        ),
      ),

      // Settings sub-screens, in their own namespace — see routes.dart for why
      // `/language` and not `/settings/language`.
      GoRoute(
        path: AppRoute.language.path,
        name: AppRoute.language.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const LanguageScreen(),
      ),
      GoRoute(
        path: AppRoute.usage.path,
        name: AppRoute.usage.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const UsageScreen(),
      ),
      GoRoute(
        path: AppRoute.about.path,
        name: AppRoute.about.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoute.help.path,
        name: AppRoute.help.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const HelpScreen(),
      ),
      GoRoute(
        path: AppRoute.privacy.path,
        name: AppRoute.privacy.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const LegalScreen(document: LegalDocument.privacy),
      ),
      GoRoute(
        path: AppRoute.terms.path,
        name: AppRoute.terms.routeName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const LegalScreen(document: LegalDocument.terms),
      ),
    ],
    errorBuilder: (_, GoRouterState state) =>
        UnknownRouteScreen(location: state.uri.toString()),
  );
});

/// The guard.
///
/// Ordering is deliberate and each step is a gate the one below depends on.
String? _redirect(Ref ref, GoRouterState state) {
  final String location = state.matchedLocation;

  // 1. Bootstrap. Everything below needs the database and the notifier.
  final AsyncValue<BootstrapResult> boot = ref.read(appBootstrapProvider);
  if (boot.isLoading || boot.hasError) {
    return location == AppRoute.splash.path ? null : AppRoute.splash.path;
  }

  // 2. First run.
  if (!ref.read(onboardingSeenProvider)) {
    return location == AppRoute.onboarding.path
        ? null
        : AppRoute.onboarding.path;
  }

  // 3. The permissions primer.
  //
  // ⚠️ A PRIMER, not a gate. If this blocked on the OS grant, a user who tapped
  // "Don't Allow" would be in a dead end the app cannot escape — iOS never
  // re-prompts, so the Continue button could never become enabled. Continue
  // always works; the Recording screen is where a still-denied microphone is
  // handled, because that is the moment the user has a reason to care.
  if (!ref.read(permissionsPrimerSeenProvider)) {
    return location == AppRoute.permissions.path
        ? null
        : AppRoute.permissions.path;
  }

  // 4. The capture family. The ROUTER owns which capture screen is up; the
  //    pipeline only advances a phase. That inversion is what makes each
  //    capture screen independently pumpable in a test, and what makes a cold
  //    start into `/capture/confirm` land on Home rather than on a confirm
  //    screen with nothing to confirm.
  if (location.startsWith(kCapturePathPrefix)) {
    final CapturePhase phase = ref.read(
      captureControllerProvider.select((CaptureState s) => s.phase),
    );
    if (phase == CapturePhase.failed) {
      // ⚠️ Except on Processing, which has no error UI: every failure after
      // Stop (too short, silence, a recogniser that died) left the user under
      // a spinner that never finished. The Recording screen underneath renders
      // every capture failure.
      return location == AppRoute.captureProcessing.path
          ? AppRoute.capture.path
          : null;
    }
    final String? allowed = captureLocationFor(phase);
    if (allowed == null) return AppRoute.home.path;
    return location == allowed ? null : allowed;
  }

  // 5. Nobody who is set up belongs on a transient screen.
  if (kTransientPaths.contains(location)) return AppRoute.home.path;

  return null;
}
