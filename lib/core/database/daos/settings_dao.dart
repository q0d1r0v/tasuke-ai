import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/tables.dart';

part 'settings_dao.g.dart';

/// Reads and writes the `app_settings` key/value table.
///
/// Everything in and out of here is a `Map<String, String>` of JSON-encoded
/// scalars. Turning that into an `AppSettings` is `AppSettingsCodec`'s job, one
/// layer up — this DAO has no opinion about which keys exist, which is exactly
/// what makes adding a preference a zero-migration change.
@DriftAccessor(tables: <Type>[SettingsEntries])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  /// The whole table as a map.
  ///
  /// All of it, not the six keys `AppSettings` happens to want: the row count is
  /// single digits, and a `WHERE key IN (...)` list is one more place to forget
  /// a key when a preference is added.
  Stream<Map<String, String>> watchAll() =>
      select(settingsEntries).watch().map(_asMap);

  Future<Map<String, String>> readAll() =>
      select(settingsEntries).get().then(_asMap);

  Future<String?> read(String key) async {
    final SettingRow? row = await (select(
      settingsEntries,
    )..where(($SettingsEntriesTable t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> put(String key, String jsonValue, {required DateTime nowUtc}) {
    return into(settingsEntries).insertOnConflictUpdate(
      SettingsEntriesCompanion(
        key: Value<String>(key),
        value: Value<String>(jsonValue),
        updatedAtUtcMs: Value<DateTime>(nowUtc),
      ),
    );
  }

  /// ⚠️ One transaction, because the settings screen writes a whole
  /// `AppSettings` snapshot at a time. Written key by key, a crash mid-write
  /// leaves a settings object that is half old and half new — and the stream
  /// would emit each intermediate state, so the UI visibly flickers through
  /// them.
  Future<void> putAll(Map<String, String> values, {required DateTime nowUtc}) {
    if (values.isEmpty) return Future<void>.value();
    return transaction(() async {
      await batch((Batch b) {
        for (final MapEntry<String, String> entry in values.entries) {
          b.insert(
            settingsEntries,
            SettingsEntriesCompanion(
              key: Value<String>(entry.key),
              value: Value<String>(entry.value),
              updatedAtUtcMs: Value<DateTime>(nowUtc),
            ),
            onConflict: DoUpdate(
              (SettingsEntries old) => SettingsEntriesCompanion(
                value: Value<String>(entry.value),
                updatedAtUtcMs: Value<DateTime>(nowUtc),
              ),
            ),
          );
        }
      });
    });
  }

  /// Puts every preference back to its shipped default.
  ///
  /// ⚠️ [SettingKeys.notificationIdCounter] is deliberately left alone. It is
  /// not a preference: the OS may still hold alarms registered against ids this
  /// database no longer explains, and rewinding the counter hands those same
  /// ids back out to new tasks.
  Future<void> resetToDefaults({required DateTime nowUtc}) {
    return transaction(() async {
      await (delete(settingsEntries)..where(
            ($SettingsEntriesTable t) =>
                t.key.equals(SettingKeys.notificationIdCounter).not(),
          ))
          .go();
      await seedDefaults(nowUtc: nowUtc);
    });
  }

  /// Writes any default that is not already present.
  ///
  /// `insertOnConflictUpdate` would be wrong here — it would overwrite the
  /// user's choices every time it ran. `DoNothing` makes this safe to call from
  /// `beforeOpen` on a database that already has rows.
  Future<void> seedDefaults({required DateTime nowUtc}) {
    return batch((Batch b) {
      for (final MapEntry<String, String> entry
          in kDefaultSettingValues.entries) {
        b.insert(
          settingsEntries,
          SettingsEntriesCompanion(
            key: Value<String>(entry.key),
            value: Value<String>(entry.value),
            updatedAtUtcMs: Value<DateTime>(nowUtc),
          ),
          onConflict: DoNothing<SettingsEntries, SettingRow>(),
        );
      }
    });
  }

  static Map<String, String> _asMap(List<SettingRow> rows) => <String, String>{
    for (final SettingRow row in rows) row.key: row.value,
  };
}
