/// The user-visible settings, as one immutable snapshot.
final class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.languageCode = 'en',
    this.allDayReminderMinute = 9 * 60,
    this.hapticsEnabled = true,
    this.batteryWarningDismissed = false,
    this.onboardingTabIndex = 0,
  });

  static const AppSettings defaults = AppSettings();

  final bool notificationsEnabled;
  final String languageCode;

  /// What time an all-day task's reminder fires. Surfaced in Settings so a
  /// user who wants their morning list at 07:00 can have it.
  final int allDayReminderMinute;

  final bool hapticsEnabled;

  /// The OEM battery-optimisation notice is shown once and then never again.
  final bool batteryWarningDismissed;

  /// Which Home tab to restore on relaunch.
  final int onboardingTabIndex;

  AppSettings copyWith({
    bool? notificationsEnabled,
    String? languageCode,
    int? allDayReminderMinute,
    bool? hapticsEnabled,
    bool? batteryWarningDismissed,
    int? onboardingTabIndex,
  }) => AppSettings(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    languageCode: languageCode ?? this.languageCode,
    allDayReminderMinute: allDayReminderMinute ?? this.allDayReminderMinute,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    batteryWarningDismissed:
        batteryWarningDismissed ?? this.batteryWarningDismissed,
    onboardingTabIndex: onboardingTabIndex ?? this.onboardingTabIndex,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.notificationsEnabled == notificationsEnabled &&
      other.languageCode == languageCode &&
      other.allDayReminderMinute == allDayReminderMinute &&
      other.hapticsEnabled == hapticsEnabled &&
      other.batteryWarningDismissed == batteryWarningDismissed &&
      other.onboardingTabIndex == onboardingTabIndex;

  @override
  int get hashCode => Object.hash(
    notificationsEnabled,
    languageCode,
    allDayReminderMinute,
    hapticsEnabled,
    batteryWarningDismissed,
    onboardingTabIndex,
  );
}

abstract interface class SettingsRepository {
  Stream<AppSettings> watch();

  Future<AppSettings> read();

  Future<void> write(AppSettings settings);
}
