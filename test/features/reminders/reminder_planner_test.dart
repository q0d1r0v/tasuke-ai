import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_plan.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

/// A civil moment in March 2026. Midweek and far from any month boundary, so a
/// failure is never ambiguous between a bug and an off-by-one in the fixture.
LocalDateTime civil(int day, int hour, [int minute = 0]) =>
    LocalDateTime(LocalDate(2026, 3, day), LocalTimeOfDay.hm(hour, minute));

Task taskWithReminder({
  required String id,
  required LocalDateTime? at,
  int? notificationId = 1,
  bool enabled = true,
  bool completed = false,
  String title = 'Send the build to James',
}) {
  final DateTime stamp = DateTime.utc(2026, 3, 11, 5);
  return Task(
    id: id,
    title: title,
    createdAt: stamp,
    updatedAt: stamp,
    completed: completed,
    due: at == null ? null : TaskDue(date: at.date, time: at.time),
    reminder: TaskReminder(
      enabled: enabled,
      at: at,
      notificationId: notificationId,
    ),
  );
}

void main() {
  /// Wednesday 11 March 2026, 10:00 on the user's own clock.
  final LocalDateTime now = civil(11, 10);

  ReminderPlan planFor(
    List<Task> tasks, {
    Set<int> held = const <int>{},
    bool notificationsEnabled = true,
  }) => ReminderPlanner.plan(
    tasks: tasks,
    now: now,
    heldIds: held,
    notificationsEnabled: notificationsEnabled,
  );

  group('what belongs in the OS', () {
    test('a future reminder on an open task is scheduled', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: civil(11, 15), notificationId: 77),
      ]);

      expect(plan.toSchedule.single.notificationId, 77);
      expect(plan.toSchedule.single.taskId, 't-1');
      expect(plan.toSchedule.single.atLocal, civil(11, 15));
      expect(plan.toCancel, isEmpty);
    });

    test('a completed task is not scheduled', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: civil(11, 15), completed: true),
      ]);

      expect(plan.toSchedule, isEmpty);
    });

    test('a task whose reminder switch is off is not scheduled', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: civil(11, 15), enabled: false),
      ]);

      expect(plan.toSchedule, isEmpty);
    });

    test('a moment already past is left alone rather than re-fired', () {
      // Not an error: "3 PM" said at 4 PM already rolled to tomorrow in the
      // parser, so anything still in the past is a knowingly backdated task.
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: civil(11, 9)),
      ]);

      expect(plan.toSchedule, isEmpty);
    });

    test('a reminder due exactly now has already passed', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: now),
      ]);

      expect(plan.toSchedule, isEmpty);
    });

    test('a task with no moment and one with no id are both skipped', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: null),
        taskWithReminder(id: 't-2', at: civil(11, 15), notificationId: null),
      ]);

      expect(plan.toSchedule, isEmpty);
    });

    test('an empty plan reports itself as empty', () {
      expect(planFor(const <Task>[]).isEmpty, isTrue);
    });
  });

  group('the rolling window', () {
    /// One more task than the window holds, all in the future, deliberately
    /// handed over in the wrong order.
    List<Task> tooManyTasks() {
      final List<Task> tasks = <Task>[
        for (int i = 0; i < ReminderPlanner.windowSize + 10; i++)
          taskWithReminder(
            id: 't-$i',
            // One per day, so the soonest is t-0 and the furthest is last.
            at: civil(11, 15).addMinutes(i * 1440),
            notificationId: 1000 + i,
          ),
      ];
      return tasks.reversed.toList();
    }

    test('is capped at windowSize however many tasks are due', () {
      // ⚠️ The cap is not a performance tweak. iOS delivers only the 64 soonest
      // pending local notifications and silently drops the rest, and Samsung
      // throws past 500 AlarmManager alarms.
      final ReminderPlan plan = planFor(tooManyTasks());

      expect(plan.toSchedule, hasLength(ReminderPlanner.windowSize));
    });

    test('keeps the SOONEST N, not the first N handed over', () {
      final ReminderPlan plan = planFor(tooManyTasks());

      expect(plan.toSchedule.first.taskId, 't-0');
      expect(
        plan.toSchedule.last.taskId,
        't-${ReminderPlanner.windowSize - 1}',
      );
      expect(
        plan.toSchedule.map((PlannedReminder r) => r.taskId),
        isNot(contains('t-${ReminderPlanner.windowSize}')),
        reason: 'the task just past the window must be the first one dropped',
      );
    });

    test('is handed over in ascending time order', () {
      final List<LocalDateTime> moments = planFor(tooManyTasks()).toSchedule
          .map((PlannedReminder r) => r.atLocal)
          .toList();

      expect(moments, orderedEquals(List<LocalDateTime>.from(moments)..sort()));
    });

    test('a reminder pushed out of the window is cancelled if held', () {
      // The OS is holding the 61st-soonest alarm from a previous sweep; a
      // newer, sooner task has since displaced it.
      final int evicted = 1000 + ReminderPlanner.windowSize;
      final ReminderPlan plan = planFor(tooManyTasks(), held: <int>{evicted});

      expect(plan.toCancel, contains(evicted));
    });
  });

  group('the orphan sweep', () {
    test('cancels ids the OS holds that nothing wants any more', () {
      // The shape of a task deleted while the process was dead: the row is
      // gone, the alarm is not.
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(id: 't-1', at: civil(11, 15), notificationId: 7),
        ],
        held: <int>{7, 8, 9},
      );

      expect(plan.toCancel, <int>[8, 9]);
      expect(plan.toSchedule.single.notificationId, 7);
    });

    test('leaves an id alone when its task is still wanted', () {
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(id: 't-1', at: civil(11, 15), notificationId: 7),
        ],
        held: <int>{7},
      );

      expect(plan.toCancel, isEmpty);
    });

    test('cancels the alarm of a task that has since been completed', () {
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(
            id: 't-1',
            at: civil(11, 15),
            notificationId: 7,
            completed: true,
          ),
        ],
        held: <int>{7},
      );

      expect(plan.toCancel, <int>[7]);
      expect(plan.toSchedule, isEmpty);
    });

    test('never cancels an alarm the OS may still be about to deliver', () {
      // 09:40 has passed, but an inexact alarm can arrive up to an hour late.
      // Cancelling it as an orphan here meant the reminder never came at all
      // when the user happened to open the app in that gap.
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(id: 't-1', at: civil(11, 9, 40), notificationId: 7),
        ],
        held: <int>{7},
      );

      expect(plan.toCancel, isEmpty);
      expect(
        plan.toSchedule,
        isEmpty,
        reason: 'a passed minute is not re-fired',
      );
    });

    test('does cancel one that is more than an hour overdue', () {
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(id: 't-1', at: civil(11, 8, 59), notificationId: 7),
        ],
        held: <int>{7},
      );

      expect(plan.toCancel, <int>[7]);
    });

    test('an in-flight alarm on a completed task is still cancelled', () {
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(
            id: 't-1',
            at: civil(11, 9, 40),
            notificationId: 7,
            completed: true,
          ),
        ],
        held: <int>{7},
      );

      expect(plan.toCancel, <int>[7]);
    });
  });

  group('the notifications kill switch', () {
    test('off cancels everything the OS holds and schedules nothing', () {
      // ⚠️ A kill switch, not a filter: a user who revokes consent stops being
      // interrupted immediately, not at the next sweep.
      final ReminderPlan plan = planFor(
        <Task>[
          taskWithReminder(id: 't-1', at: civil(11, 15), notificationId: 7),
        ],
        held: <int>{7, 8},
        notificationsEnabled: false,
      );

      expect(plan.toSchedule, isEmpty);
      expect(plan.toCancel..sort(), <int>[7, 8]);
    });

    test('off with nothing held is a no-op rather than a cancel storm', () {
      final ReminderPlan plan = planFor(<Task>[
        taskWithReminder(id: 't-1', at: civil(11, 15)),
      ], notificationsEnabled: false);

      expect(plan.isEmpty, isTrue);
    });
  });

  group('notificationIdFor', () {
    test('is the same id every time for the same task', () {
      expect(
        ReminderPlanner.notificationIdFor('b3f1-0000-4000-8000-000000000001'),
        ReminderPlanner.notificationIdFor('b3f1-0000-4000-8000-000000000001'),
        reason: 'editing a task must target the alarm slot it already owns',
      );
    });

    test('differs for ids that differ only in the last character', () {
      expect(
        ReminderPlanner.notificationIdFor('task-a'),
        isNot(ReminderPlanner.notificationIdFor('task-b')),
      );
    });

    test('is never negative and always fits a signed 32-bit request code', () {
      // ⚠️ Android's AlarmManager request codes are signed 32-bit ints, and a
      // negative id is silently dropped on some OEM builds — the alarm simply
      // never arrives and nothing reports an error.
      final List<String> ids = <String>[
        '',
        'a',
        'ЁЁЁ',
        '👩‍👩‍👧‍👦',
        'x' * 500,
        'b3f1c0de-0000-4000-8000-000000000001',
      ];
      for (final String id in ids) {
        final int value = ReminderPlanner.notificationIdFor(id);
        expect(value, greaterThan(0), reason: 'id "$id" folded to $value');
        expect(value, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('never returns the 0 several plugins use as a sentinel', () {
      // The FNV fold can reach 0; the shift off it is what this pins.
      for (int i = 0; i < 2000; i++) {
        expect(ReminderPlanner.notificationIdFor('task-$i'), isNot(0));
      }
    });
  });
}
