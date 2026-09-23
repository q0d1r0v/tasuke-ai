/// The complete set of `SharedPreferences` keys.
///
/// ⚠️ There is a rule behind what is here: **only state that must be read
/// synchronously, or that describes the OS rather than the user's data, lives
/// here** — the router's flags and what we have learned about the platform's
/// permission prompts. Everything else a user can change is a row in
/// `app_settings`, where it is transactional, observable and wiped by "Delete
/// all data" along with the tasks.
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

  /// Whether the app has already sent the user to Android's "Alarms &
  /// reminders" page once, on its own initiative.
  ///
  /// ⚠️ Once. `SCHEDULE_EXACT_ALARM` has no dialog: requesting it opens a
  /// system settings page and takes the user out of the app. Doing that on
  /// every reminder saved would be a punishment; doing it never left every
  /// reminder on Android 14+ inexact — up to a quarter of an hour late —
  /// because the permission is off by default there. After the first time,
  /// the Home banner is the way back.
  static const String exactAlarmPrompted = 'exact_alarm_prompted';

  /// Prefix for "the OS said no for good" per permission, suffixed with the
  /// `AppPermission` name.
  ///
  /// ⚠️ Android cannot report that from a status check — `status` says
  /// `denied` for "never asked", "asked once" and "never ask again" alike. Only
  /// a request reveals it. Without remembering the answer, every later tap on
  /// the Home banner re-requested, the OS silently refused, and the tap did
  /// nothing at all.
  static const String permissionRefusedPrefix = 'permission_refused_';
}
