import 'dart:convert';

import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/daos/settings_dao.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';

/// The type safety the key/value table gives up, in one tested function.
///
/// Every read is total: a missing key, a key holding the wrong JSON type and a
/// key holding malformed JSON all fall back to the shipped default rather than
/// throwing. ⚠️ That is not defensiveness for its own sake — the settings row
/// is read on the way to the first frame, and a `FormatException` there is a
/// white screen on launch with no way for the user to recover short of
/// reinstalling and losing every task.
abstract final class AppSettingsCodec {
  static AppSettings decode(Map<String, String> raw) => AppSettings(
    notificationsEnabled: _bool(
      raw,
      SettingKeys.notificationsEnabled,
      AppSettings.defaults.notificationsEnabled,
    ),
    languageCode: _string(
      raw,
      SettingKeys.languageCode,
      AppSettings.defaults.languageCode,
    ),
    allDayReminderMinute: _minuteOfDay(
      raw,
      SettingKeys.allDayReminderMinute,
      AppSettings.defaults.allDayReminderMinute,
    ),
    hapticsEnabled: _bool(
      raw,
      SettingKeys.hapticsEnabled,
      AppSettings.defaults.hapticsEnabled,
    ),
    batteryWarningDismissed: _bool(
      raw,
      SettingKeys.batteryWarningDismissed,
      AppSettings.defaults.batteryWarningDismissed,
    ),
    onboardingTabIndex: _int(
      raw,
      SettingKeys.onboardingTabIndex,
      AppSettings.defaults.onboardingTabIndex,
    ),
  );

  static Map<String, String> encode(AppSettings settings) => <String, String>{
    SettingKeys.notificationsEnabled: jsonEncode(settings.notificationsEnabled),
    SettingKeys.languageCode: jsonEncode(settings.languageCode),
    SettingKeys.allDayReminderMinute: jsonEncode(settings.allDayReminderMinute),
    SettingKeys.hapticsEnabled: jsonEncode(settings.hapticsEnabled),
    SettingKeys.batteryWarningDismissed: jsonEncode(
      settings.batteryWarningDismissed,
    ),
    SettingKeys.onboardingTabIndex: jsonEncode(settings.onboardingTabIndex),
  };

  static Object? _raw(Map<String, String> raw, String key) {
    final String? encoded = raw[key];
    if (encoded == null) return null;
    try {
      return jsonDecode(encoded);
    } on FormatException {
      // The key, never the value: a setting's value is small but it is still
      // the user's, and a log line is the one place it could leak.
      Log.w('setting "$key" is not valid JSON; using the default');
      return null;
    }
  }

  static bool _bool(Map<String, String> raw, String key, bool fallback) {
    final Object? value = _raw(raw, key);
    return value is bool ? value : fallback;
  }

  static int _int(Map<String, String> raw, String key, int fallback) {
    final Object? value = _raw(raw, key);
    return value is int ? value : fallback;
  }

  static String _string(Map<String, String> raw, String key, String fallback) {
    final Object? value = _raw(raw, key);
    return value is String && value.isNotEmpty ? value : fallback;
  }

  /// ⚠️ Range-checked, unlike the others. `allDayReminderMinute` is handed
  /// straight to `LocalTimeOfDay`, whose constructor asserts `0 <= m < 1440` —
  /// so a value outside the range is a crash in release mode's absence of
  /// asserts turning into a reminder scheduled on the wrong day.
  static int _minuteOfDay(Map<String, String> raw, String key, int fallback) {
    final int value = _int(raw, key, fallback);
    return value >= 0 && value < 1440 ? value : fallback;
  }
}

final class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository({required this.dao, required this.clock});

  final SettingsDao dao;
  final Clock clock;

  @override
  Stream<AppSettings> watch() => dao.watchAll().map(AppSettingsCodec.decode);

  @override
  Future<AppSettings> read() async =>
      AppSettingsCodec.decode(await dao.readAll());

  /// Writes the whole snapshot, not a diff.
  ///
  /// A diff would need the previous value, which means a read, which means the
  /// two can race — and the loser silently un-does a toggle the user just
  /// flipped. Six rows in one transaction is cheaper than getting that right.
  @override
  Future<void> write(AppSettings settings) =>
      dao.putAll(AppSettingsCodec.encode(settings), nowUtc: clock.nowUtc());

  /// Back to factory defaults, for "Delete all data".
  ///
  /// Not part of [SettingsRepository]: it is a destructive maintenance action,
  /// and putting it on the port would put it one autocomplete away from the
  /// settings screen's ordinary [write].
  Future<void> resetToDefaults() => dao.resetToDefaults(nowUtc: clock.nowUtc());
}
