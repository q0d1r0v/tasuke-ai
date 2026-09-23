/// Every route in the app.
enum AppRoute {
  splash('/splash'),
  onboarding('/onboarding'),
  permissions('/permissions'),

  /// The permissions screen again, after first run, opened from the Home
  /// warning banner.
  ///
  /// ⚠️ Its own path, not `/permissions`. `/permissions` is in
  /// [kTransientPaths], so the guard bounces a set-up user off it to Home —
  /// which made the banner's "Tap to fix" land right back where it started.
  access('/access'),

  // ── Shell branches: the four bottom-nav destinations ───────────────────────
  home('/home'),
  search('/search'),
  stats('/stats'),
  settings('/settings'),

  // ── The capture flow. Three routes under one prefix, above the shell ───────
  capture('/capture'),
  captureProcessing('/capture/processing'),
  captureConfirm('/capture/confirm'),

  taskDetail('/task/:id'),
  paywall('/paywall'),

  // ── Settings sub-screens, in their OWN namespace ───────────────────────────
  //
  // ⚠️ `/language`, NOT `/settings/language`, and this is not a style choice.
  // `/settings` is a StatefulShellBranch route; a top-level route that extends
  // a branch's path is ambiguous — go_router can match either, so it "works in
  // the test and shows a different screen on the device".
  //
  // They also sit above the shell for a second reason: the notched nav bar and
  // its mic button would otherwise float over a legal document.
  language('/language'),
  usage('/usage'),
  about('/about'),
  help('/help'),
  privacy('/legal/privacy'),
  terms('/legal/terms');

  const AppRoute(this.path);

  final String path;

  /// go_router's `name`, used so call sites never retype a path string.
  String get routeName => name;
}

/// Why the paywall is up, when the user did not open it themselves.
///
/// Carried as the `reason` query parameter rather than as `extra`, so it
/// survives every way of getting there — the mic's `push`, a failure screen's
/// `go`, a restored route — and the paywall builder can read it back.
enum PaywallReason {
  /// The mic, once the day's free captures are spent.
  quota;

  static const String _parameter = 'reason';

  /// The paywall's location, opened for this reason: `/paywall?reason=quota`.
  String get location => Uri(
    path: AppRoute.paywall.path,
    queryParameters: <String, String>{_parameter: name},
  ).toString();

  /// The reason in a paywall location's [query], or null for a paywall the
  /// user opened themselves (Settings → Subscription, Usage → See Pro plans).
  static PaywallReason? fromQuery(Map<String, String> query) =>
      values.asNameMap()[query[_parameter]];
}

/// Matched by prefix because the guard compares [kTransientPaths] as exact
/// strings and the capture family has three members.
const String kCapturePathPrefix = '/capture';

/// The location of one task's detail page.
///
/// A function rather than three hand-written `'/task/${task.id}'` strings, so a
/// change to [AppRoute.taskDetail] has one place to follow it. The reminder
/// re-entry path in particular must not be a typo away from a blank screen.
String taskDetailLocation(String taskId) => '/task/$taskId';

/// Reachable only before the app is set up. A configured user is bounced off.
const Set<String> kTransientPaths = <String>{
  '/splash',
  '/onboarding',
  '/permissions',
};

/// The four bottom-nav destinations, in bar order. The mic button occupies the
/// middle slot and is not a destination.
const List<AppRoute> kShellBranches = <AppRoute>[
  AppRoute.home,
  AppRoute.search,
  AppRoute.stats,
  AppRoute.settings,
];
