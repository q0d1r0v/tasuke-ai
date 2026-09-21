import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/settings_dao.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/features/settings/data/drift_settings_repository.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';

import 'database_test_kit.dart';

void main() {
  late AppDatabase db;
  late SettingsDao dao;
  final DateTime now = kTestNowLocal.toUtc();

  setUp(() {
    db = openTestDatabase();
    dao = db.settingsDao;
  });

  tearDown(() => db.close());

  group('seeding', () {
    test('a fresh database already holds every default', () async {
      final Map<String, String> raw = await dao.readAll();
      expect(raw.keys.toSet(), kDefaultSettingValues.keys.toSet());
      expect(raw, kDefaultSettingValues);
    });

    test('the seeded values decode to AppSettings.defaults', () async {
      expect(
        AppSettingsCodec.decode(await dao.readAll()),
        AppSettings.defaults,
      );
    });

    test('re-seeding never overwrites a user choice', () async {
      await dao.put(SettingKeys.hapticsEnabled, 'false', nowUtc: now);
      await dao.seedDefaults(nowUtc: now);

      expect(await dao.read(SettingKeys.hapticsEnabled), 'false');
    });
  });

  group('reads and writes', () {
    test('put then read round-trips a JSON scalar', () async {
      await dao.put(SettingKeys.languageCode, '"en"', nowUtc: now);
      expect(await dao.read(SettingKeys.languageCode), '"en"');
    });

    test('a missing key reads as null rather than throwing', () async {
      expect(await dao.read('no_such_key'), isNull);
    });

    test('putAll applies every key', () async {
      await dao.putAll(<String, String>{
        SettingKeys.notificationsEnabled: 'false',
        SettingKeys.allDayReminderMinute: '420',
      }, nowUtc: now);

      final Map<String, String> raw = await dao.readAll();
      expect(raw[SettingKeys.notificationsEnabled], 'false');
      expect(raw[SettingKeys.allDayReminderMinute], '420');
      // Untouched keys survive.
      expect(raw[SettingKeys.hapticsEnabled], 'true');
    });

    test('putAll with nothing to write is a no-op', () async {
      final Map<String, String> before = await dao.readAll();
      await dao.putAll(const <String, String>{}, nowUtc: now);
      expect(await dao.readAll(), before);
    });

    test('watchAll re-emits after a write', () async {
      final Future<List<Map<String, String>>> collected = dao
          .watchAll()
          .take(2)
          .toList();

      await pumpEventQueue();
      await dao.put(SettingKeys.hapticsEnabled, 'false', nowUtc: now);

      final List<Map<String, String>> emissions = await collected;
      expect(emissions.first[SettingKeys.hapticsEnabled], 'true');
      expect(emissions.last[SettingKeys.hapticsEnabled], 'false');
    });
  });

  group('resetToDefaults', () {
    test('restores preferences', () async {
      await dao.put(SettingKeys.hapticsEnabled, 'false', nowUtc: now);
      await dao.put(SettingKeys.allDayReminderMinute, '420', nowUtc: now);

      await dao.resetToDefaults(nowUtc: now);

      expect(
        AppSettingsCodec.decode(await dao.readAll()),
        AppSettings.defaults,
      );
    });

    test(
      'keeps the notification counter so old alarm ids are not reused',
      () async {
        await db.tasksDao.nextNotificationId(nowUtc: now);
        await db.tasksDao.nextNotificationId(nowUtc: now);

        await dao.resetToDefaults(nowUtc: now);

        expect(await dao.read(SettingKeys.notificationIdCounter), '2');
        expect(await db.tasksDao.nextNotificationId(nowUtc: now), 3);
      },
    );

    test('drops a stray key that is no longer a known setting', () async {
      await dao.put('removed_in_v3', '"junk"', nowUtc: now);
      await dao.resetToDefaults(nowUtc: now);
      expect(await dao.read('removed_in_v3'), isNull);
    });
  });

  group('AppSettingsCodec', () {
    test('round-trips a non-default snapshot', () {
      const AppSettings settings = AppSettings(
        notificationsEnabled: false,
        languageCode: 'en',
        allDayReminderMinute: 7 * 60,
        hapticsEnabled: false,
        batteryWarningDismissed: true,
        onboardingTabIndex: 2,
      );

      expect(
        AppSettingsCodec.decode(AppSettingsCodec.encode(settings)),
        settings,
      );
    });

    test('an empty map is the defaults, not a crash', () {
      expect(
        AppSettingsCodec.decode(const <String, String>{}),
        AppSettings.defaults,
      );
    });

    test(
      'malformed JSON falls back instead of throwing on the launch path',
      () {
        final AppSettings settings = AppSettingsCodec.decode(<String, String>{
          SettingKeys.hapticsEnabled: 'not json at all',
          SettingKeys.allDayReminderMinute: '{',
        });

        expect(settings, AppSettings.defaults);
      },
    );

    test('a value of the wrong JSON type falls back', () {
      final AppSettings settings = AppSettingsCodec.decode(<String, String>{
        // A bool where an int belongs, and a number where a bool belongs.
        SettingKeys.allDayReminderMinute: 'true',
        SettingKeys.hapticsEnabled: '1',
      });

      expect(
        settings.allDayReminderMinute,
        AppSettings.defaults.allDayReminderMinute,
      );
      expect(settings.hapticsEnabled, AppSettings.defaults.hapticsEnabled);
    });

    test('an out-of-range reminder minute falls back', () {
      // LocalTimeOfDay asserts 0 <= m < 1440, and asserts are off in release —
      // so an unchecked 3000 here becomes a reminder two days late.
      for (final String encoded in <String>['-1', '1440', '3000']) {
        expect(
          AppSettingsCodec.decode(<String, String>{
            SettingKeys.allDayReminderMinute: encoded,
          }).allDayReminderMinute,
          AppSettings.defaults.allDayReminderMinute,
        );
      }
      expect(
        AppSettingsCodec.decode(<String, String>{
          SettingKeys.allDayReminderMinute: '1439',
        }).allDayReminderMinute,
        1439,
      );
    });

    test('an empty language code falls back rather than breaking lookups', () {
      expect(
        AppSettingsCodec.decode(<String, String>{
          SettingKeys.languageCode: '""',
        }).languageCode,
        'en',
      );
    });
  });

  group('DriftSettingsRepository', () {
    test('write then read round-trips through the database', () async {
      final DriftSettingsRepository repository = DriftSettingsRepository(
        dao: dao,
        clock: FixedClock(kTestNowLocal),
      );

      const AppSettings settings = AppSettings(
        notificationsEnabled: false,
        allDayReminderMinute: 8 * 60,
        onboardingTabIndex: 1,
      );
      await repository.write(settings);

      expect(await repository.read(), settings);
      expect(await repository.watch().first, settings);
    });
  });
}
