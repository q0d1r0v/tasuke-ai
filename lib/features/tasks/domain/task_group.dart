import 'package:tasuke_ai/core/time/local_date.dart';

import 'task.dart';

/// Which header a group of tasks gets on the Upcoming and Completed lists.
///
/// The label is an enum rather than a string because the string is an ARB
/// lookup and the domain layer has no BuildContext.
enum TaskGroupLabel {
  today,
  tomorrow,

  /// Within the next seven days — rendered as the weekday name.
  weekday,

  /// Beyond seven days but inside the next calendar week block.
  nextWeek,

  /// Two weeks out and beyond — a range, rendered as "Later".
  later,

  /// Completed lists group by the day the task was finished.
  completedOn,
}

/// A labelled run of tasks sharing a date.
final class TaskGroup {
  const TaskGroup({
    required this.label,
    required this.date,
    required this.tasks,
  });

  final TaskGroupLabel label;
  final LocalDate date;
  final List<Task> tasks;

  /// Folds an ordered, flat list into labelled sections.
  ///
  /// Takes `today` explicitly rather than reading a clock, which is what makes
  /// every grouping case a one-line test.
  static List<TaskGroup> groupByDate(
    List<Task> tasks, {
    required LocalDate today,
  }) {
    final Map<String, List<Task>> byDate = <String, List<Task>>{};
    for (final Task task in tasks) {
      final LocalDate? date = task.due?.date;
      if (date == null) continue;
      byDate.putIfAbsent(date.toIso(), () => <Task>[]).add(task);
    }

    final List<String> keys = byDate.keys.toList()..sort();
    final List<TaskGroup> groups = keys.map((String key) {
      final LocalDate date = LocalDate.parseIso(key);
      return TaskGroup(
        label: labelFor(date, today: today),
        date: date,
        tasks: byDate[key]!,
      );
    }).toList();

    return _mergeRangeLabels(groups);
  }

  /// Collapses consecutive groups that would render the same header.
  ///
  /// ⚠️ [TaskGroupLabel.nextWeek] and [TaskGroupLabel.later] describe a RANGE,
  /// not a day: every date 7–13 days out is "Next Week". Grouping strictly by
  /// date therefore produces "Next Week" twice in a row the moment two tasks
  /// land on different days of the same week, which reads as a rendering bug.
  /// [TaskGroupLabel.weekday] is left alone on purpose — "Saturday" and
  /// "Tuesday" are different headers and both belong.
  static List<TaskGroup> _mergeRangeLabels(List<TaskGroup> groups) {
    const Set<TaskGroupLabel> ranges = <TaskGroupLabel>{
      TaskGroupLabel.nextWeek,
      TaskGroupLabel.later,
      TaskGroupLabel.today,
    };

    final List<TaskGroup> merged = <TaskGroup>[];
    for (final TaskGroup group in groups) {
      final TaskGroup? previous = merged.isEmpty ? null : merged.last;
      if (previous != null &&
          previous.label == group.label &&
          ranges.contains(group.label)) {
        merged[merged.length - 1] = TaskGroup(
          label: previous.label,
          // The earliest date in the run, so the ordering the caller relies on
          // is unchanged.
          date: previous.date,
          tasks: <Task>[...previous.tasks, ...group.tasks],
        );
        continue;
      }
      merged.add(group);
    }
    return merged;
  }

  /// Groups completed tasks by the local day they were completed on, newest
  /// first.
  static List<TaskGroup> groupByCompletion(
    List<Task> tasks, {
    required LocalDate today,
  }) {
    final Map<String, List<Task>> byDate = <String, List<Task>>{};
    for (final Task task in tasks) {
      final DateTime? at = task.completedAt;
      if (at == null) continue;
      final DateTime local = at.toLocal();
      final LocalDate date = LocalDate(local.year, local.month, local.day);
      byDate.putIfAbsent(date.toIso(), () => <Task>[]).add(task);
    }

    final List<String> keys = byDate.keys.toList()
      ..sort((String a, String b) => b.compareTo(a));
    return keys
        .map(
          (String key) => TaskGroup(
            label: TaskGroupLabel.completedOn,
            date: LocalDate.parseIso(key),
            tasks: byDate[key]!,
          ),
        )
        .toList();
  }

  static TaskGroupLabel labelFor(LocalDate date, {required LocalDate today}) {
    final int delta = date.differenceInDays(today);
    if (delta <= 0) return TaskGroupLabel.today;
    if (delta == 1) return TaskGroupLabel.tomorrow;
    if (delta <= 6) return TaskGroupLabel.weekday;
    if (delta <= 13) return TaskGroupLabel.nextWeek;
    return TaskGroupLabel.later;
  }

  @override
  bool operator ==(Object other) =>
      other is TaskGroup &&
      other.label == label &&
      other.date == date &&
      other.tasks.length == tasks.length;

  @override
  int get hashCode => Object.hash(label, date, tasks.length);
}
