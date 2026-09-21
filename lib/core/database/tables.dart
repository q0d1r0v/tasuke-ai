import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/database/converters.dart';

/// ## The time split, which is this schema's central decision
///
/// Every timestamp in `tasks` belongs to exactly one of two families, and
/// mixing them is the bug this comment exists to prevent.
///
/// **UTC instants** — `created_at_utc_ms`, `updated_at_utc_ms`,
/// `completed_at_utc_ms`. These answer *"when did this happen"*. They are
/// points on the world's timeline, stored as epoch milliseconds, and they are
/// correct forever regardless of where the phone is or what the zone rules do.
///
/// **Local civil wall-clock, with no offset at all** — `due_date`,
/// `due_minute_of_day`, `reminder_at_local`. These answer *"when should this
/// fire on the user's clock"*. They are appointments, not instants, and the
/// absolute moment is resolved at scheduling time against whatever zone the
/// device is in *then*.
///
/// ⚠️ Two real failure modes justify the split, and both are things users
/// notice immediately:
///
///  1. **Travel.** Someone in Tashkent says "tomorrow at 3 PM" and flies to
///     London. If the due time were stored as an instant (UTC+5 3 PM = 10:00Z)
///     the reminder arrives at 11 AM London time. What they meant — and what
///     they will still mean after landing — is 3 PM on the clock in front of
///     them. A civil date-time gives them that; an instant cannot.
///  2. **Daylight saving.** A recurring 08:00 alarm stored as an instant is an
///     hour wrong on the far side of every DST transition, and *stays* wrong
///     until someone edits it. A civil date-time re-resolves each time it is
///     scheduled, so the transition costs nothing.
///
/// The inverse mistake is just as bad: storing `completed_at` as a civil
/// string makes "completed in the last 7 days" unanswerable, because two rows
/// written either side of a flight are no longer comparable.
///
/// ## Why `due_date` is TEXT and not an epoch day
///
/// ISO-8601 `'YYYY-MM-DD'` sorts lexicographically in true chronological
/// order. That single property means `ORDER BY due_date, due_minute_of_day` is
/// simultaneously correct, served straight out of a b-tree index, and readable
/// when someone opens the file in a `sqlite3` shell at 2 AM. An epoch day is
/// none of the last one and buys nothing.
@DataClassName('TaskRow')
@TableIndex(
  name: 'tasks_pending_due',
  columns: <Symbol>{#completed, #dueDate, #dueMinuteOfDay},
)
@TableIndex(name: 'tasks_due_date', columns: <Symbol>{#dueDate})
// The reminder window's index.
//
// ⚠️ Composite, and the column order is the whole point. On `reminderAtLocal`
// alone SQLite prefers `tasks_pending_due` — `completed = 0` is an equality
// constraint and equality wins — and then sorts the result through a temp
// B-tree. Leading with the two equality columns lets one index serve the
// filter *and* the ORDER BY, which is what keeps the sweep cheap as the table
// grows. `EXPLAIN QUERY PLAN` in self_schema_test.dart pins it.
@TableIndex(
  name: 'tasks_reminder_at',
  columns: <Symbol>{#completed, #reminderEnabled, #reminderAtLocal},
)
@TableIndex(name: 'tasks_completed_at', columns: <Symbol>{#completedAtUtcMs})
class Tasks extends Table {
  /// A client-generated uuid v4. Not an autoincrement integer: ids are minted
  /// on the Confirm screen before anything is written, so the drafts the user
  /// is editing already carry the identity the rows will have.
  TextColumn get id => text()();

  TextColumn get title => text()();

  /// [title] lowercased with diacritics stripped, written on every save.
  ///
  /// Search is `LIKE '%needle%'` against this column rather than against
  /// [title], because SQLite's `LIKE` is only case-insensitive for ASCII and
  /// knows nothing about diacritics — "Café" would not match "cafe". Folding
  /// once at write time is also the only way the comparison stays cheap.
  TextColumn get titleFolded => text()();

  TextColumn get notes => text().nullable()();

  /// Local civil date, `'YYYY-MM-DD'`. Null means the task has no due date at
  /// all, which is a different thing from an all-day task — see
  /// [dueMinuteOfDay].
  TextColumn get dueDate => text().nullable().map(const LocalDateConverter())();

  /// Minutes since local midnight, 0..1439. Null means all-day.
  IntColumn get dueMinuteOfDay => integer().nullable()();

  BoolColumn get reminderEnabled =>
      boolean().withDefault(const Constant<bool>(false))();

  /// Minutes *before* the due time the reminder fires. 0 = at the time.
  IntColumn get reminderLeadMinutes =>
      integer().withDefault(const Constant<int>(0))();

  /// The resolved civil moment, `'YYYY-MM-DDTHH:MM'`. Denormalised on purpose:
  /// the scheduler's hot query is "the next 64 reminders at or after now",
  /// and one indexed string comparison answers it without recomputing
  /// date + time - lead for every row in the table.
  TextColumn get reminderAtLocal =>
      text().nullable().map(const LocalDateTimeConverter())();

  /// The OS alarm slot this task owns.
  ///
  /// ⚠️ Stable for the life of the task. Editing a task must retarget the same
  /// slot, otherwise cancel-then-schedule leaks an alarm and the user gets two
  /// notifications for one task.
  IntColumn get notificationId => integer().nullable()();

  BoolColumn get completed =>
      boolean().withDefault(const Constant<bool>(false))();

  /// UTC epoch ms. Null iff [completed] is false.
  IntColumn get completedAtUtcMs =>
      integer().nullable().map(const UtcInstantConverter())();

  IntColumn get createdAtUtcMs => integer().map(const UtcInstantConverter())();

  IntColumn get updatedAtUtcMs => integer().map(const UtcInstantConverter())();

  /// `TaskSource.name` — `voice` or `manual`. Stored as the enum's name rather
  /// than its index so that reordering the enum cannot silently rewrite
  /// history.
  TextColumn get source => text()();

  /// ⚠️ What the user actually said. This is the most sensitive column in the
  /// database: it never leaves the device, never reaches a log (pass it through
  /// `Log.redact`), and never appears in an error message.
  TextColumn get sourceTranscript => text().nullable()();

  /// Groups every task produced by one utterance, so "discard all" and a
  /// future undo can act on the batch rather than on rows one at a time.
  TextColumn get captureId => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Settings as key/value rather than as one wide row.
///
/// A one-row settings table needs a schema migration for every new preference
/// — and a migration is exactly the thing most likely to go wrong in an app
/// with no backend and therefore no second copy of the user's data. This needs
/// none: a new preference is a new key with a default.
///
/// The cost is that type safety leaves the schema. It comes back in
/// `AppSettingsCodec`, which is one pure function with one test file, instead
/// of being spread across a dozen columns.
@DataClassName('SettingRow')
class SettingsEntries extends Table {
  /// ⚠️ The Dart class is `SettingsEntries` but the SQL table is
  /// `app_settings`: the obvious Dart name, `AppSettings`, is already the
  /// domain snapshot class in `features/settings/domain`, and having two
  /// `AppSettings` types in scope in the settings DAO is how a mapper ends up
  /// importing the wrong one.
  @override
  String get tableName => 'app_settings';

  TextColumn get key => text()();

  /// A JSON-encoded scalar — `true`, `540`, `"en"`. JSON rather than a bare
  /// string so that `false` and `"false"` stay distinguishable.
  TextColumn get value => text()();

  IntColumn get updatedAtUtcMs => integer().map(const UtcInstantConverter())();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// One row per **local** calendar day of voice usage.
///
/// ⚠️ Keyed on a local date, not a UTC one, and that is the whole point: the
/// free quota has to reset at the user's own midnight. Keyed on a UTC day, a
/// user in Tashkent (UTC+5) would find their allowance resetting at 5 AM, and
/// one in Los Angeles at 4 or 5 PM the previous afternoon.
@DataClassName('UsageDayRow')
class UsageDays extends Table {
  /// `'YYYY-MM-DD'`, local.
  TextColumn get day => text()();

  /// ⚠️ Only **successful** captures are counted. A capture that hit silence
  /// or failed to transcribe must not consume quota — charging for those is
  /// the complaint users actually file.
  IntColumn get captureCount => integer().withDefault(const Constant<int>(0))();

  IntColumn get taskCount => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{day};
}

/// The keys of the `app_settings` table.
///
/// These live beside the table rather than in the feature that reads them
/// because in a key/value table the key set *is* the schema. A key added in a
/// feature file and a default seeded here would drift apart the first time
/// someone renamed one.
abstract final class SettingKeys {
  static const String notificationsEnabled = 'notifications_enabled';
  static const String languageCode = 'language_code';
  static const String allDayReminderMinute = 'all_day_reminder_minute';
  static const String hapticsEnabled = 'haptics_enabled';
  static const String batteryWarningDismissed = 'battery_warning_dismissed';
  static const String onboardingTabIndex = 'onboarding_tab_index';

  /// The monotonic counter behind `TasksDao.nextNotificationId`. Deliberately
  /// not surfaced in `AppSettings`: it is bookkeeping, not a preference, and
  /// nothing outside the DAO may write it.
  static const String notificationIdCounter = 'notification_id_counter';
}

/// The rows written on `wasCreated`.
///
/// Seeding beats "absent means default" at read time for one reason: the
/// settings screen can then write a single key without first having to
/// materialise every other one, and a `SELECT` on a fresh install returns the
/// same shape as on an old one.
///
/// Values are JSON scalars, matching the column's contract.
const Map<String, String> kDefaultSettingValues = <String, String>{
  SettingKeys.notificationsEnabled: 'true',
  SettingKeys.languageCode: '"en"',
  SettingKeys.allDayReminderMinute: '540',
  SettingKeys.hapticsEnabled: 'true',
  SettingKeys.batteryWarningDismissed: 'false',
  SettingKeys.onboardingTabIndex: '0',
  SettingKeys.notificationIdCounter: '0',
};
