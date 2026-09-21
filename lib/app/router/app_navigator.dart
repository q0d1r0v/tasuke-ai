import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';

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
