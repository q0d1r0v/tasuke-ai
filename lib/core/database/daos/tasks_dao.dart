import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/core/time/local_date.dart';

part 'tasks_dao.g.dart';

/// Every statement that touches `tasks`.
///
/// ⚠️ Nothing here reads a clock. Every method that writes a timestamp takes
/// `nowUtc`, which is what lets a test insert a task "three days ago" without
/// touching the system clock, and what keeps `DateTime.now()` confined to
/// `core/clock`.
///
/// ⚠️ Nothing here knows the words "Tomorrow", "Friday" or "Next week" either.
/// Grouping is `TaskGroup.groupByDate` in Dart: the labels are ARB lookups, and
/// a SQL layer that emits them cannot be localised and cannot be tested without
/// a database.
@DriftAccessor(tables: <Type>[Tasks, SettingsEntries])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.attachedDatabase);

  /// The default page size for the reminder window.
  ///
  /// iOS caps an app at 64 pending local notifications and silently drops the
  /// rest, so the scheduler works a rolling window of exactly that size rather
  /// than trying to register every future reminder.
  static const int kReminderWindow = 64;

  /// Android's `AlarmManager` request code and `flutter_local_notifications`'
  /// Android id are both a Java `int`. A value above this wraps to negative
  /// when it crosses the platform channel, and the alarm lands in a slot the
  /// app cannot cancel.
  static const int kMaxNotificationId = 0x7FFFFFFF;

  /// `due_date IS NULL ASC, due_date ASC, due_minute_of_day IS NULL DESC,
  /// due_minute_of_day ASC, sort_order ASC`.
  ///
  /// Two things a list has to get right, and neither is what SQLite does by
  /// default:
  ///
  ///  * **Undated tasks sort last.** Plain `due_date ASC` puts NULL first, so
  ///    every "someday" idea would sit above the things due this morning.
  ///    `due_date IS NULL ASC` (false before true) pushes them to the tail.
  ///  * **Within a day, all-day sorts before timed.** An all-day task is the
  ///    heading for the day, not something that happens after 23:59 — so the
  ///    NULL minute has to come first, which is `IS NULL DESC`.
  ///
  /// ⚠️ The second key is DESC on purpose. It would be easy to "tidy" both `IS
  /// NULL` terms to ASC for symmetry, and the only visible effect would be that
  /// all-day tasks quietly move to the bottom of every day.
  static List<OrderingTerm Function($TasksTable t)> get _dueOrder =>
      <OrderingTerm Function($TasksTable t)>[
        ($TasksTable t) => OrderingTerm.asc(t.dueDate.isNull()),
        ($TasksTable t) => OrderingTerm.asc(t.dueDate),
        ($TasksTable t) => OrderingTerm.desc(t.dueMinuteOfDay.isNull()),
        ($TasksTable t) => OrderingTerm.asc(t.dueMinuteOfDay),
        ($TasksTable t) => OrderingTerm.asc(t.sortOrder),
      ];

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Open tasks that are undated or due on/before [today].
  ///
  /// "On or before", not "on": an overdue task belongs on today's list, because
  /// a list that hides it is a list that lets the user forget it.
  Stream<List<TaskRow>> watchToday(LocalDate today) {
    final String todayIso = today.toIso();
    return (select(tasks)
          ..where(
            ($TasksTable t) =>
                t.completed.equals(false) &
                (t.dueDate.isNull() |
                    t.dueDate.isSmallerOrEqualValue(todayIso)),
          )
          ..orderBy(_dueOrder))
        .watch();
  }

  /// Open tasks due strictly after [today], flat and ordered. The caller folds
  /// them into labelled sections.
  Stream<List<TaskRow>> watchUpcoming(LocalDate today, {int limit = 500}) {
    final String todayIso = today.toIso();
    return (select(tasks)
          ..where(
            ($TasksTable t) =>
                t.completed.equals(false) &
                t.dueDate.isBiggerThanValue(todayIso),
          )
          ..orderBy(_dueOrder)
          ..limit(limit))
        .watch();
  }

  /// Open tasks with no due date at all.
  Stream<List<TaskRow>> watchSomeday({int limit = 500}) {
    return (select(tasks)
          ..where(
            ($TasksTable t) => t.completed.equals(false) & t.dueDate.isNull(),
          )
          ..orderBy(<OrderingTerm Function($TasksTable t)>[
            ($TasksTable t) => OrderingTerm.asc(t.sortOrder),
            ($TasksTable t) => OrderingTerm.desc(t.createdAtUtcMs),
          ])
          ..limit(limit))
        .watch();
  }

  /// Completed tasks, most recently finished first.
  Stream<List<TaskRow>> watchCompleted({int limit = 200}) {
    return (select(tasks)
          ..where(($TasksTable t) => t.completed.equals(true))
          ..orderBy(<OrderingTerm Function($TasksTable t)>[
            ($TasksTable t) => OrderingTerm.desc(t.completedAtUtcMs),
          ])
          ..limit(limit))
        .watch();
  }

  /// [folded] must already have been through [foldForSearch] — the same
  /// function that produced `title_folded` on write. Folding one side only is
  /// how "Café" stops matching itself.
  ///
  /// Open tasks come first: someone searching is almost always looking for
  /// something they still have to do.
  Stream<List<TaskRow>> watchSearch(String folded, {int limit = 100}) {
    if (folded.isEmpty) return Stream<List<TaskRow>>.value(const <TaskRow>[]);
    return (select(tasks)
          ..where(($TasksTable t) => t.titleFolded.like('%$folded%'))
          ..orderBy(<OrderingTerm Function($TasksTable t)>[
            ($TasksTable t) => OrderingTerm.asc(t.completed),
            ..._dueOrder,
          ])
          ..limit(limit))
        .watch();
  }

  Stream<TaskRow?> watchById(String id) => (select(
    tasks,
  )..where(($TasksTable t) => t.id.equals(id))).watchSingleOrNull();

  Future<TaskRow?> findById(String id) => (select(
    tasks,
  )..where(($TasksTable t) => t.id.equals(id))).getSingleOrNull();

  /// The next reminders due at or after [fromLocalIso] (`'YYYY-MM-DDTHH:MM'`).
  ///
  /// The comparison is a plain string comparison because ISO-8601 sorts
  /// lexicographically, so this is one range scan on `tasks_reminder_at` — no
  /// date functions, and nothing that depends on the sqlite process's idea of
  /// the local timezone.
  Future<List<TaskRow>> dueReminders(
    String fromLocalIso, {
    int limit = kReminderWindow,
  }) {
    return (select(tasks)
          ..where(
            ($TasksTable t) =>
                t.completed.equals(false) &
                t.reminderEnabled.equals(true) &
                t.reminderAtLocal.isBiggerOrEqualValue(fromLocalIso),
          )
          ..orderBy(<OrderingTerm Function($TasksTable t)>[
            ($TasksTable t) => OrderingTerm.asc(t.reminderAtLocal),
          ])
          ..limit(limit))
        .get();
  }

  /// Every future reminder, unbounded.
  ///
  /// Used by the orphan sweep after a timezone change or a reboot, where the
  /// whole point is to compare the full set against what the OS actually holds
  /// — a window would leave the tail scheduled at the old offset forever.
  Future<List<TaskRow>> allSchedulable(String fromLocalIso) {
    return (select(tasks)
          ..where(
            ($TasksTable t) =>
                t.completed.equals(false) &
                t.reminderEnabled.equals(true) &
                t.reminderAtLocal.isBiggerOrEqualValue(fromLocalIso),
          )
          ..orderBy(<OrderingTerm Function($TasksTable t)>[
            ($TasksTable t) => OrderingTerm.asc(t.reminderAtLocal),
          ]))
        .get();
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// One utterance's worth of tasks, in **one** transaction.
  ///
  /// ⚠️ Not a loop of inserts. A capture that produced five tasks and crashed
  /// after three would leave the user with a partial list they never dictated
  /// and no way to tell which two are missing. It is also 5 fsyncs instead of
  /// 1, which on a cold mid-range Android is the difference between the Confirm
  /// screen dismissing instantly and visibly hanging.
  Future<void> insertDrafts(List<TasksCompanion> rows) {
    if (rows.isEmpty) return Future<void>.value();
    return transaction(() => batch((Batch b) => b.insertAll(tasks, rows)));
  }

  Future<void> insertTask(TasksCompanion row) => into(tasks).insert(row);

  Future<void> setCompleted(
    String id, {
    required bool completed,
    required DateTime nowUtc,
  }) {
    return (update(tasks)..where(($TasksTable t) => t.id.equals(id))).write(
      TasksCompanion(
        completed: Value<bool>(completed),
        // Cleared on un-complete, so `completed_at` can never describe a task
        // that is not finished — the Stats streak counts rows by this column.
        completedAtUtcMs: completed
            ? Value<DateTime?>(nowUtc)
            : const Value<DateTime?>(null),
        updatedAtUtcMs: Value<DateTime>(nowUtc),
      ),
    );
  }

  Future<void> updateTask(String id, TasksCompanion values) =>
      (update(tasks)..where(($TasksTable t) => t.id.equals(id))).write(values);

  Future<void> deleteTask(String id) =>
      (delete(tasks)..where(($TasksTable t) => t.id.equals(id))).go();

  /// ⚠️ Deletes tasks only. The notification-id counter in `app_settings`
  /// survives on purpose: the OS may still hold alarms that were registered
  /// against ids this table no longer explains, and restarting the counter at 1
  /// would hand those ids straight back out.
  Future<void> deleteAll() => delete(tasks).go();

  // ── Notification ids ───────────────────────────────────────────────────────

  /// Hands out the next OS alarm slot.
  ///
  /// ⚠️ Read-modify-write inside a transaction, not `MAX(notification_id) + 1`.
  /// The max over live rows reuses the id of a task the user just deleted,
  /// which collides with an alarm the OS has not dropped yet; and two saves
  /// racing on the same read both get the same id, which means one task's
  /// reminder silently overwrites the other's.
  ///
  /// The counter wraps at [kMaxNotificationId] rather than growing: it lives in
  /// a Java `int` on Android, and at one id per save a wrap is roughly two
  /// billion captures away, by which point the colliding slot is long gone.
  Future<int> nextNotificationId({required DateTime nowUtc}) {
    return transaction(() async {
      final SettingRow? row =
          await (select(settingsEntries)..where(
                ($SettingsEntriesTable t) =>
                    t.key.equals(SettingKeys.notificationIdCounter),
              ))
              .getSingleOrNull();
      final int current = int.tryParse(row?.value ?? '') ?? 0;
      final int next = current >= kMaxNotificationId ? 1 : current + 1;
      await into(settingsEntries).insertOnConflictUpdate(
        SettingsEntriesCompanion(
          key: const Value<String>(SettingKeys.notificationIdCounter),
          value: Value<String>(next.toString()),
          updatedAtUtcMs: Value<DateTime>(nowUtc),
        ),
      );
      return next;
    });
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  /// The raw material for `TaskStats`, re-read on every write to `tasks`.
  ///
  /// ⚠️ The completion instants come back as instants and are bucketed into
  /// local days **in Dart**. The tempting SQL —
  /// `date(completed_at_utc_ms / 1000, 'unixepoch', 'localtime')` — asks the C
  /// library in whichever isolate sqlite3 was opened on what "local" means, and
  /// that is not guaranteed to agree with Dart's `toLocal()`: drift runs
  /// statements on a background isolate, and `TZ` is not part of what crosses
  /// the boundary. Two different answers to "which day was this?" is a streak
  /// that breaks at midnight for some users and not others.
  Stream<TaskStatsRows> watchStatsRows({
    required DateTime windowStartUtc,
    int windowLimit = 2000,
  }) {
    return _statsTicker().asyncMap(
      (QueryRow _) => readStatsRows(
        windowStartUtc: windowStartUtc,
        windowLimit: windowLimit,
      ),
    );
  }

  /// A one-shot read of the same rows [watchStatsRows] streams.
  Future<TaskStatsRows> readStatsRows({
    required DateTime windowStartUtc,
    int windowLimit = 2000,
  }) {
    return transaction(() async {
      final QueryRow totals = await customSelect(
        'SELECT '
        '(SELECT COUNT(*) FROM tasks WHERE completed = 0) AS pending, '
        '(SELECT COUNT(*) FROM tasks WHERE completed = 1) AS completed_total',
        readsFrom: {tasks},
      ).getSingle();

      // Only the one column: these rows exist to be counted, and a `SELECT *`
      // here would pull every `source_transcript` in the window into memory to
      // draw a bar chart.
      final List<TypedResult> completions =
          await (selectOnly(tasks)
                ..addColumns(<Expression<Object>>[tasks.completedAtUtcMs])
                ..where(
                  tasks.completed.equals(true) &
                      tasks.completedAtUtcMs.isBiggerOrEqualValue(
                        windowStartUtc.toUtc().millisecondsSinceEpoch,
                      ),
                )
                ..orderBy(<OrderingTerm>[
                  OrderingTerm.desc(tasks.completedAtUtcMs),
                ])
                ..limit(windowLimit))
              .get();

      return TaskStatsRows(
        pending: totals.read<int>('pending'),
        completedTotal: totals.read<int>('completed_total'),
        recentCompletions: <DateTime>[
          for (final TypedResult row in completions)
            // The range predicate already excluded NULL — in SQL
            // `NULL >= x` is NULL, not true — so this never drops a row.
            if (row.readWithConverter(tasks.completedAtUtcMs)
                case final DateTime at)
              at,
        ],
      );
    });
  }

  /// A query whose *result value* changes on every insert, update and delete.
  ///
  /// ⚠️ This indirection is not decoration. Drift's stream queries emit only
  /// when the result differs from the previous one, so a ticker of
  /// `SELECT COUNT(*)` would go silent for edits, and a ticker of
  /// `SELECT MAX(updated_at)` would go silent when the newest task is deleted.
  /// The row count plus the sum of `updated_at_utc_ms` moves for all three,
  /// because every writer in this DAO bumps `updated_at_utc_ms`.
  Stream<QueryRow> _statsTicker() => customSelect(
    'SELECT COUNT(*) AS n, COALESCE(SUM(updated_at_utc_ms), 0) AS checksum '
    'FROM tasks',
    readsFrom: {tasks},
  ).watchSingle();
}

/// What one stats read returns. Deliberately dumb: the arithmetic that turns
/// this into `TaskStats` needs `today`, and `today` is not the database's
/// business.
final class TaskStatsRows {
  const TaskStatsRows({
    required this.pending,
    required this.completedTotal,
    required this.recentCompletions,
  });

  static const TaskStatsRows empty = TaskStatsRows(
    pending: 0,
    completedTotal: 0,
    recentCompletions: <DateTime>[],
  );

  final int pending;
  final int completedTotal;

  /// UTC instants, newest first, bounded by the window the caller asked for.
  final List<DateTime> recentCompletions;
}
