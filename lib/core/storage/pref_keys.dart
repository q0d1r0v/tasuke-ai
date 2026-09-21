/// The complete set of `SharedPreferences` keys.
///
/// ⚠️ Two keys, and there is a rule behind the number rather than an accident:
/// **only state that `GoRouter.redirect` needs lives here.** Everything else a
/// user can change is a row in `app_settings`, where it is transactional,
/// observable and wiped by "Delete all data" along with the tasks.
///
/// See `core/storage/prefs.dart` for why the router's flags cannot live in the
/// database.
abstract final class PrefKeys {
  /// Whether the three onboarding pages have been seen through to the end.
  static const String onboardingSeen = 'onboarding_seen';

  /// Whether the pre-permission explainer has been shown.
  ///
  /// Distinct from "the permission is granted": the OS answers that, and it can
  /// flip either way from Settings at any time. This records only that we have
  /// already spent the user's patience explaining ourselves once.
  static const String permissionsPrimerSeen = 'permissions_primer_seen';
}
