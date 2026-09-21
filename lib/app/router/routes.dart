/// Every route in the app.
enum AppRoute {
  splash('/splash'),
  onboarding('/onboarding'),
  permissions('/permissions'),
  modelSetup('/model-setup'),

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

/// Matched by prefix because the guard compares [kTransientPaths] as exact
/// strings and the capture family has three members.
const String kCapturePathPrefix = '/capture';

/// Reachable only before the app is set up. A configured user is bounced off.
const Set<String> kTransientPaths = <String>{
  '/splash',
  '/onboarding',
  '/permissions',
  '/model-setup',
};

/// The four bottom-nav destinations, in bar order. The mic button occupies the
/// middle slot and is not a destination.
const List<AppRoute> kShellBranches = <AppRoute>[
  AppRoute.home,
  AppRoute.search,
  AppRoute.stats,
  AppRoute.settings,
];
