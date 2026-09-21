import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

/// Wednesday 2026-04-22, the date the store screenshots are taken on.
const LocalDate today = LocalDate(2026, 4, 22);

Task taskOn(LocalDate date, {String title = 'Task', int? minute}) {
  final DateTime at = DateTime.utc(2026, 4, 22, 5);
  return Task(
    id: '$title-${date.toIso()}',
    title: title,
    createdAt: at,
    updatedAt: at,
    due: TaskDue(
      date: date,
      time: minute == null ? null : LocalTimeOfDay(minute),
    ),
  );
}

void main() {
  group('labelFor', () {
    test('today, tomorrow, the rest of the week, then the ranges', () {
      expect(TaskGroup.labelFor(today, today: today), TaskGroupLabel.today);
      expect(
        TaskGroup.labelFor(today.addDays(1), today: today),
        TaskGroupLabel.tomorrow,
      );
      expect(
        TaskGroup.labelFor(today.addDays(4), today: today),
        TaskGroupLabel.weekday,
      );
      expect(
        TaskGroup.labelFor(today.addDays(7), today: today),
        TaskGroupLabel.nextWeek,
      );
      expect(
        TaskGroup.labelFor(today.addDays(30), today: today),
        TaskGroupLabel.later,
      );
    });

    test('anything overdue collapses into today rather than a past header', () {
      expect(
        TaskGroup.labelFor(today.addDays(-5), today: today),
        TaskGroupLabel.today,
      );
    });
  });

  group('groupByDate', () {
    test('one header per day inside the coming week', () {
      final List<TaskGroup> groups = TaskGroup.groupByDate(<Task>[
        taskOn(today.addDays(3), title: 'Check App Store'),
        taskOn(today.addDays(6), title: 'Update app screenshots'),
      ], today: today);

      expect(groups.length, 2);
      expect(
        groups.map((TaskGroup g) => g.label),
        everyElement(TaskGroupLabel.weekday),
      );
    });

    test('two dates in the same week share ONE "Next Week" header', () {
      // ⚠️ The bug this test exists for: `nextWeek` describes a RANGE, so
      // grouping strictly by date rendered "Next Week" twice in a row the
      // moment two tasks landed on different days of it. It looked like a
      // rendering fault and it shipped into a store screenshot.
      final List<TaskGroup> groups = TaskGroup.groupByDate(<Task>[
        taskOn(today.addDays(7), title: 'Plan marketing'),
        taskOn(today.addDays(8), title: 'Team meeting', minute: 11 * 60),
      ], today: today);

      expect(groups.length, 1);
      expect(groups.single.label, TaskGroupLabel.nextWeek);
      expect(groups.single.tasks.length, 2);
      // The run keeps the earliest date, so the caller's ordering is unchanged.
      expect(groups.single.date, today.addDays(7));
    });

    test('distinct weekdays are NOT merged — they are different headers', () {
      final List<TaskGroup> groups = TaskGroup.groupByDate(<Task>[
        taskOn(today.addDays(3), title: 'Saturday thing'),
        taskOn(today.addDays(6), title: 'Tuesday thing'),
      ], today: today);

      expect(groups.length, 2);
    });

    test('several far-future dates share one "Later" header', () {
      final List<TaskGroup> groups = TaskGroup.groupByDate(<Task>[
        taskOn(today.addDays(30)),
        taskOn(today.addDays(60)),
        taskOn(today.addDays(90)),
      ], today: today);

      expect(groups.length, 1);
      expect(groups.single.label, TaskGroupLabel.later);
      expect(groups.single.tasks.length, 3);
    });

    test('undated tasks are left out entirely', () {
      final DateTime at = DateTime.utc(2026, 4, 22, 5);
      final List<TaskGroup> groups = TaskGroup.groupByDate(<Task>[
        Task(id: 'someday', title: 'Someday', createdAt: at, updatedAt: at),
      ], today: today);

      expect(groups, isEmpty);
    });

    test('an empty list groups to nothing rather than throwing', () {
      expect(TaskGroup.groupByDate(const <Task>[], today: today), isEmpty);
    });
  });

  group('groupByCompletion', () {
    test('newest completion day first', () {
      final Task older = taskOn(
        today,
        title: 'Older',
      ).copyWith(completed: true, completedAt: DateTime.utc(2026, 4, 20, 9));
      final Task newer = taskOn(
        today,
        title: 'Newer',
      ).copyWith(completed: true, completedAt: DateTime.utc(2026, 4, 21, 9));

      final List<TaskGroup> groups = TaskGroup.groupByCompletion(<Task>[
        older,
        newer,
      ], today: today);

      expect(groups.length, 2);
      expect(groups.first.tasks.single.title, 'Newer');
    });

    test('a completed task with no timestamp is skipped, not crashed on', () {
      final Task orphan = taskOn(today).copyWith(completed: true);
      expect(
        TaskGroup.groupByCompletion(<Task>[orphan], today: today),
        isEmpty,
      );
    });
  });
}
