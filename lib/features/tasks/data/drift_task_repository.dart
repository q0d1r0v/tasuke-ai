import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/tasks/data/task_mapper.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';
import 'package:uuid/uuid.dart';

/// How far back the stats query looks.
///
/// It bounds two things at once: the streak (a streak longer than this reads as
/// exactly this) and the number of rows a stats read touches. Just over a year
/// is long enough that nobody real hits the cap and short enough that the query
/// stays a range scan on `tasks_completed_at`.
const int kStatsWindowDays = 400;

/// [TaskRepository] over Drift.
///
/// The repository is where "a list of rows" becomes "what a screen renders":
/// grouping, the stats arithmetic and the reminder resolution all happen here,
/// in Dart, where `today` is an argument and every case is a one-line test.
final class DriftTaskRepository implements TaskRepository {
  DriftTaskRepository({
    required this.dao,
    required this.clock,
    this.uuid = const Uuid(),
  });

  final TasksDao dao;
  final Clock clock;
  final Uuid uuid;

  @override
  Stream<List<Task>> watchToday(LocalDate today) =>
      dao.watchToday(today).map(TaskMapper.toTasks);

  @override
  Stream<List<TaskGroup>> watchUpcoming(LocalDate today) => dao
      .watchUpcoming(today)
      .map(
        (List<TaskRow> rows) =>
            TaskGroup.groupByDate(TaskMapper.toTasks(rows), today: today),
      );

  @override
  Stream<List<TaskGroup>> watchCompleted(LocalDate today, {int limit = 200}) =>
      dao
          .watchCompleted(limit: limit)
          .map(
            (List<TaskRow> rows) => TaskGroup.groupByCompletion(
              TaskMapper.toTasks(rows),
              today: today,
            ),
          );

  @override
  Stream<List<Task>> watchSomeday() =>
      dao.watchSomeday().map(TaskMapper.toTasks);

  /// ⚠️ The query is folded here, with the same function that produced
  /// `title_folded` on write. Search is the one feature where an asymmetry
  /// between the two sides is invisible in code review and obvious to the user.
  @override
  Stream<List<Task>> watchSearch(String query, {int limit = 100}) => dao
      .watchSearch(foldForSearch(query), limit: limit)
      .map(TaskMapper.toTasks);

  @override
  Stream<Task?> watchById(String id) => dao
      .watchById(id)
      .map((TaskRow? row) => row == null ? null : TaskMapper.toTask(row));

  @override
  Future<Task?> findById(String id) async {
    final TaskRow? row = await dao.findById(id);
    return row == null ? null : TaskMapper.toTask(row);
  }

  @override
  Future<List<Task>> pendingReminders(
    LocalDateTime from, {
    int limit = TasksDao.kReminderWindow,
  }) async =>
      TaskMapper.toTasks(await dao.dueReminders(from.toIso(), limit: limit));

  @override
  Future<List<Task>> allSchedulable(LocalDateTime from) async =>
      TaskMapper.toTasks(await dao.allSchedulable(from.toIso()));

  /// ⚠️ Persists only. Nothing here talks to the notifier.
  ///
  /// Scheduling is a different module with a different failure mode: the OS can
  /// refuse an alarm (exact-alarm permission, doze, the 64-notification cap) and
  /// that must not roll back a save the user already saw succeed. This method's
  /// contract is that the rows come out correct and `reminder_at_local` is
  /// resolved; whoever schedules reads them back.
  @override
  Future<List<Task>> saveDrafts(
    List<TaskDraft> drafts, {
    required String captureId,
    required int allDayReminderMinute,
  }) async {
    if (drafts.isEmpty) return const <Task>[];

    final DateTime nowUtc = clock.nowUtc();
    final List<Task> tasks = <Task>[];
    for (int i = 0; i < drafts.length; i++) {
      final TaskDraft draft = drafts[i];
      final bool wantsReminder = draft.hasReminder && draft.date != null;
      tasks.add(
        TaskMapper.fromDraft(
          draft,
          id: uuid.v4(),
          captureId: captureId,
          allDayReminderMinute: allDayReminderMinute,
          nowUtc: nowUtc,
          // Only tasks that will actually be scheduled consume an id, so the
          // counter tracks alarms rather than saves.
          notificationId: wantsReminder
              ? await dao.nextNotificationId(nowUtc: nowUtc)
              : null,
          // The order the user left the Confirm cards in.
          sortOrder: i,
        ),
      );
    }

    await dao.insertDrafts(tasks.map(TaskMapper.toCompanion).toList());
    Log.d('saved ${tasks.length} task(s) for capture $captureId');
    return tasks;
  }

  @override
  Future<Task> create(
    TaskDraft draft, {
    required int allDayReminderMinute,
  }) async {
    final DateTime nowUtc = clock.nowUtc();
    final bool wantsReminder = draft.hasReminder && draft.date != null;
    final Task task = TaskMapper.fromDraft(
      draft,
      id: uuid.v4(),
      // A manually created task belongs to no utterance.
      captureId: null,
      allDayReminderMinute: allDayReminderMinute,
      nowUtc: nowUtc,
      notificationId: wantsReminder
          ? await dao.nextNotificationId(nowUtc: nowUtc)
          : null,
    );
    await dao.insertTask(TaskMapper.toCompanion(task));
    return task;
  }

  /// ⚠️ `updatedAt` is stamped here and the caller's value is ignored. It is
  /// the only thing the stats stream watches to know something changed, and a
  /// caller that forgot to bump it would make the Stats screen stop updating
  /// for reasons nobody would connect to an edit screen.
  @override
  Future<Task> update(Task task) async {
    final Task stamped = task.copyWith(updatedAt: clock.nowUtc());
    await dao.updateTask(stamped.id, TaskMapper.toCompanion(stamped));
    return stamped;
  }

  @override
  Future<void> setCompleted(String id, {required bool completed}) =>
      dao.setCompleted(id, completed: completed, nowUtc: clock.nowUtc());

  @override
  Future<void> delete(String id) => dao.deleteTask(id);

  @override
  Future<void> deleteAll() => dao.deleteAll();

  @override
  Stream<TaskStats> watchStats(LocalDate today) {
    // ⚠️ The one place a civil date is turned into an instant, and it is a
    // deliberately loose lower bound: local midnight of the oldest day we care
    // about, minus a day of slack. The slack absorbs the fact that the device's
    // offset today is not necessarily its offset 400 days ago — a DST
    // transition inside the window would otherwise shave an hour off the edge
    // and drop the oldest day's completions.
    final DateTime windowStartUtc = today
        .addDays(-(kStatsWindowDays + 1))
        .toDateTimeLocal()
        .toUtc();

    return dao
        .watchStatsRows(windowStartUtc: windowStartUtc)
        .map((TaskStatsRows rows) => toStats(rows, today: today));
  }

  /// Pure, so every streak and week-boundary case is a table test with no
  /// database in it.
  static TaskStats toStats(TaskStatsRows rows, {required LocalDate today}) {
    // Bucketed in Dart, by local day — see the note on `watchStatsRows` for why
    // SQLite's `'localtime'` modifier cannot be trusted to agree with Dart's.
    final Map<String, int> byDay = <String, int>{};
    for (final DateTime at in rows.recentCompletions) {
      final DateTime local = at.toLocal();
      final String key = LocalDate(local.year, local.month, local.day).toIso();
      byDay[key] = (byDay[key] ?? 0) + 1;
    }

    // Seven counts, oldest first, ending today — the order the bar chart draws.
    final List<int> completionsByDay = <int>[
      for (int back = 6; back >= 0; back--)
        byDay[today.addDays(-back).toIso()] ?? 0,
    ];

    // "This week" is the same rolling seven days the chart shows, not the
    // calendar week. A calendar week would make the headline number disagree
    // with the bars underneath it every Monday, which reads as a bug.
    int completedThisWeek = 0;
    for (final int count in completionsByDay) {
      completedThisWeek += count;
    }

    return TaskStats(
      pending: rows.pending,
      completedTotal: rows.completedTotal,
      completedThisWeek: completedThisWeek,
      streakDays: _streak(byDay, today: today),
      completionsByDay: completionsByDay,
    );
  }

  /// Consecutive days with at least one completion, ending today.
  ///
  /// ⚠️ Today counts as a grace day: a user who has finished nothing *yet*
  /// today keeps yesterday's streak. Without that, a thirty-day streak reads as
  /// zero every morning until the first task is ticked, and the number people
  /// come back for looks broken for most of every day.
  static int _streak(Map<String, int> byDay, {required LocalDate today}) {
    final bool doneToday = (byDay[today.toIso()] ?? 0) > 0;
    int streak = 0;
    int back = doneToday ? 0 : 1;
    // Bounded by the window the query filled `byDay` from — past that point
    // the map is empty for reasons that have nothing to do with the user.
    while (streak < kStatsWindowDays) {
      if ((byDay[today.addDays(-back).toIso()] ?? 0) == 0) break;
      streak++;
      back++;
    }
    return streak;
  }
}
