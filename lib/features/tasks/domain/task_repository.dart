import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'task.dart';
import 'task_draft.dart';
import 'task_group.dart';

/// The read/write port over stored tasks.
///
/// Every method takes the dates it needs rather than reading a clock, so a
/// fake implementation in a widget test is a list and a `Stream.value`.
abstract interface class TaskRepository {
  /// Today tab: not completed, and either undated or due on/before [today].
  Stream<List<Task>> watchToday(LocalDate today);

  /// Upcoming tab: not completed, due strictly after [today], already grouped.
  Stream<List<TaskGroup>> watchUpcoming(LocalDate today);

  /// Completed tab, newest first, grouped by completion day.
  Stream<List<TaskGroup>> watchCompleted(LocalDate today, {int limit});

  /// Tasks with no due date at all.
  Stream<List<Task>> watchSomeday();

  /// Free-text search over titles, case- and diacritic-insensitive.
  Stream<List<Task>> watchSearch(String query, {int limit});

  Stream<Task?> watchById(String id);

  Future<Task?> findById(String id);

  /// The next [limit] reminders due at or after [from], in order. Feeds the
  /// rolling notification window.
  Future<List<Task>> pendingReminders(LocalDateTime from, {int limit});

  /// Every task whose reminder is enabled and in the future — used by the
  /// orphan sweep after a timezone change or a reboot.
  Future<List<Task>> allSchedulable(LocalDateTime from);

  /// Writes a whole capture in one transaction and returns the saved tasks.
  Future<List<Task>> saveDrafts(
    List<TaskDraft> drafts, {
    required String captureId,
    required int allDayReminderMinute,
  });

  Future<Task> create(TaskDraft draft, {required int allDayReminderMinute});

  Future<Task> update(Task task);

  Future<void> setCompleted(String id, {required bool completed});

  Future<void> delete(String id);

  Future<void> deleteAll();

  /// Counters for the Stats screen.
  Stream<TaskStats> watchStats(LocalDate today);
}

/// What the Stats screen renders.
final class TaskStats {
  const TaskStats({
    required this.pending,
    required this.completedTotal,
    required this.completedThisWeek,
    required this.streakDays,
    required this.completionsByDay,
  });

  static const TaskStats empty = TaskStats(
    pending: 0,
    completedTotal: 0,
    completedThisWeek: 0,
    streakDays: 0,
    completionsByDay: <int>[0, 0, 0, 0, 0, 0, 0],
  );

  final int pending;
  final int completedTotal;
  final int completedThisWeek;

  /// Consecutive days, ending today, with at least one completion.
  final int streakDays;

  /// Seven counts, oldest first, ending today. Drives the bar chart.
  final List<int> completionsByDay;

  @override
  bool operator ==(Object other) =>
      other is TaskStats &&
      other.pending == pending &&
      other.completedTotal == completedTotal &&
      other.completedThisWeek == completedThisWeek &&
      other.streakDays == streakDays &&
      other.completionsByDay.length == completionsByDay.length;

  @override
  int get hashCode =>
      Object.hash(pending, completedTotal, completedThisWeek, streakDays);
}
