import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'routes.dart';

/// The one door a controller has into the router.
///
/// A port rather than a direct `GoRouter` read so that a controller under test
/// records where it tried to go instead of needing a live router.
typedef AppNavigator = void Function(String location);

/// ⚠️ Always `go`, never `push`.
///
/// On a cold start the router may still be on `/splash` when a notification tap
/// arrives. A route pushed over the splash sits on a page the redirect never
/// re-runs for, so the user ends up on a task screen with no way back to Home.
final Provider<AppNavigator> appNavigatorProvider = Provider<AppNavigator>(
  (Ref ref) =>
      (String location) => ref.read(routerProvider).go(location),
);

/// Opens one task because its reminder was tapped.
typedef ReminderOpener = void Function(String taskId);

/// ⚠️ `go` to Home **and then** `push` the task — two calls, in that order,
/// and both are load-bearing.
///
/// `go` first because the tap can land while the router is still on `/splash`:
/// a page pushed over the splash sits on a location the redirect never re-runs
/// for. Going to Home re-runs the guard and leaves the splash behind.
///
/// `push` second because `/task/:id` is a top-level route on the root
/// navigator. A bare `go` there leaves a one-page stack, and `TasukeScaffold`'s
/// back arrow is `Navigator.maybePop` — silently inert with nothing to pop —
/// while the system Back gesture backgrounds the app instead. Seating Home
/// underneath is what gives the user a way out.
final Provider<ReminderOpener> reminderOpenerProvider =
    Provider<ReminderOpener>((Ref ref) {
      return (String taskId) {
        final GoRouter router = ref.read(routerProvider);
        router.go(AppRoute.home.path);
        router.push<void>(taskDetailLocation(taskId));
      };
    });
