import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

final DateTime at = DateTime.utc(2026, 9, 21, 9);

Task makeTask({
  String id = 'task-1',
  String title = 'Send the build to James',
  TaskDue? due,
  TaskReminder reminder = TaskReminder.none,
  bool completed = false,
  DateTime? completedAt,
}) {
  return Task(
    id: id,
    title: title,
    createdAt: at,
    updatedAt: at,
    due: due,
    reminder: reminder,
    completed: completed,
    completedAt: completedAt,
  );
}

void main() {
  group('TaskDue', () {
    test('no time means all day', () {
      const TaskDue allDay = TaskDue(date: LocalDate(2026, 9, 21));
      expect(allDay.isAllDay, isTrue);

      const TaskDue timed = TaskDue(
        date: LocalDate(2026, 9, 21),
        time: LocalTimeOfDay.hm(15, 0),
      );
      expect(timed.isAllDay, isFalse);
    });

    test('resolve falls back to the all-day minute, and only then', () {
      // ⚠️ An all-day task still needs a wall-clock time for its REMINDER.
      // The two are independent: the task has no time, the reminder does.
      const TaskDue allDay = TaskDue(date: LocalDate(2026, 9, 21));
      expect(allDay.resolve(allDayMinute: 9 * 60).toIso(), '2026-09-21T09:00');

      const TaskDue timed = TaskDue(
        date: LocalDate(2026, 9, 21),
        time: LocalTimeOfDay.hm(15, 0),
      );
      expect(timed.resolve(allDayMinute: 9 * 60).toIso(), '2026-09-21T15:00');
    });

    test('copyWith can clear the time without clearing the date', () {
      const TaskDue timed = TaskDue(
        date: LocalDate(2026, 9, 21),
        time: LocalTimeOfDay.hm(15, 0),
      );
      final TaskDue cleared = timed.copyWith(clearTime: true);
      expect(cleared.date, const LocalDate(2026, 9, 21));
      expect(cleared.time, isNull);

      final TaskDue moved = timed.copyWith(date: const LocalDate(2026, 9, 22));
      expect(moved.time, const LocalTimeOfDay.hm(15, 0));
    });

    test('equality, hashCode and toString', () {
      const TaskDue a = TaskDue(date: LocalDate(2026, 9, 21));
      const TaskDue b = TaskDue(date: LocalDate(2026, 9, 21));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('all-day'));
      expect(
        const TaskDue(
          date: LocalDate(2026, 9, 21),
          time: LocalTimeOfDay.hm(15, 0),
        ).toString(),
        contains('15:00'),
      );
    });
  });

  group('TaskReminder', () {
    test('is schedulable only when enabled AND resolved', () {
      expect(TaskReminder.none.isSchedulable, isFalse);
      expect(
        const TaskReminder(enabled: true).isSchedulable,
        isFalse,
        reason: 'enabled with nothing to fire against is not schedulable',
      );

      final TaskReminder ready = TaskReminder(
        enabled: true,
        at: LocalDateTime.parseIso('2026-09-21T15:00'),
        notificationId: 7,
      );
      expect(ready.isSchedulable, isTrue);
    });

    test('copyWith can clear the resolved instant', () {
      final TaskReminder ready = TaskReminder(
        enabled: true,
        at: LocalDateTime.parseIso('2026-09-21T15:00'),
      );
      expect(ready.copyWith(clearAt: true).at, isNull);
      expect(ready.copyWith(leadMinutes: 15).leadMinutes, 15);
      expect(ready.copyWith(enabled: false).at, isNotNull);
    });

    test('equality and hashCode', () {
      const TaskReminder a = TaskReminder(enabled: true, leadMinutes: 10);
      const TaskReminder b = TaskReminder(enabled: true, leadMinutes: 10);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == TaskReminder.none, isFalse);
    });
  });

  group('Task', () {
    test(
      'overdue is answered on the CALENDAR, never against a UTC instant',
      () {
        // ⚠️ "Is this overdue" is a question about the user's own calendar.
        // Comparing UTC instants gets it wrong for half the world for part of
        // every day — and never in a test run in UTC+0.
        final Task yesterday = makeTask(
          due: const TaskDue(date: LocalDate(2026, 9, 20)),
        );
        expect(yesterday.isOverdue(const LocalDate(2026, 9, 21)), isTrue);
        expect(yesterday.isOverdue(const LocalDate(2026, 9, 20)), isFalse);

        final Task done = makeTask(
          due: const TaskDue(date: LocalDate(2026, 9, 20)),
          completed: true,
        );
        expect(
          done.isOverdue(const LocalDate(2026, 9, 21)),
          isFalse,
          reason: 'a finished task is never overdue',
        );

        expect(makeTask().isOverdue(const LocalDate(2026, 9, 21)), isFalse);
      },
    );

    test('hasDate, isAllDay and isDueOn', () {
      final Task someday = makeTask();
      expect(someday.hasDate, isFalse);
      expect(someday.isAllDay, isTrue);
      expect(someday.isDueOn(const LocalDate(2026, 9, 21)), isFalse);

      final Task timed = makeTask(
        due: const TaskDue(
          date: LocalDate(2026, 9, 21),
          time: LocalTimeOfDay.hm(15, 0),
        ),
      );
      expect(timed.hasDate, isTrue);
      expect(timed.isAllDay, isFalse);
      expect(timed.isDueOn(const LocalDate(2026, 9, 21)), isTrue);
    });

    test('copyWith keeps identity and can clear the optional fields', () {
      final Task task = makeTask(
        due: const TaskDue(date: LocalDate(2026, 9, 21)),
        completed: true,
        completedAt: at,
      ).copyWith(notes: 'with a note');

      expect(task.copyWith(title: 'Renamed').id, 'task-1');
      expect(task.copyWith(title: 'Renamed').createdAt, at);
      expect(task.copyWith(clearDue: true).due, isNull);
      expect(task.copyWith(clearNotes: true).notes, isNull);
      expect(task.copyWith(clearCompletedAt: true).completedAt, isNull);
      expect(task.copyWith(sortOrder: 3).sortOrder, 3);
      expect(task.copyWith(source: TaskSource.voice).source, TaskSource.voice);
    });

    test('equality, hashCode and toString', () {
      expect(makeTask(), makeTask());
      expect(makeTask().hashCode, makeTask().hashCode);
      expect(makeTask() == makeTask(title: 'Other'), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(makeTask() == 'task-1', isFalse);
      expect(makeTask().toString(), contains('Send the build to James'));
      expect(makeTask().toString(), contains('someday'));
    });
  });

  group('TaskSource', () {
    test('an unknown or missing name falls back to manual', () {
      expect(TaskSource.fromName('voice'), TaskSource.voice);
      expect(TaskSource.fromName('manual'), TaskSource.manual);
      // A row written by a future version must not crash this one.
      expect(TaskSource.fromName('telepathy'), TaskSource.manual);
      expect(TaskSource.fromName(null), TaskSource.manual);
    });
  });

  group('TaskTitle', () {
    test('collapses whitespace and trims', () {
      expect(TaskTitle.normalise('  Send   the\tbuild \n'), 'Send the build');
      expect(TaskTitle.normalise(''), '');
      expect(TaskTitle.normalise('   '), '');
    });

    test('truncates on a GRAPHEME boundary, not a code unit', () {
      // ⚠️ Cutting by code unit splits surrogate pairs and ZWJ sequences, and
      // the result renders as a replacement character rather than as a shorter
      // title. The input here is a model's output, so this is reachable.
      final String long = '👨‍👩‍👧‍👦 ' * 40;
      final String result = TaskTitle.normalise(long);
      expect(result.length, lessThanOrEqualTo(Task.maxTitleLength));
      expect(result.contains('�'), isFalse);
    });

    test('a long ASCII title is clamped to the layout limit', () {
      final String result = TaskTitle.normalise('a' * 500);
      expect(result.length, lessThanOrEqualTo(Task.maxTitleLength));
    });

    test('isValid rejects whitespace-only titles', () {
      expect(TaskTitle.isValid('Send the build'), isTrue);
      expect(TaskTitle.isValid('   '), isFalse);
      expect(TaskTitle.isValid(''), isFalse);
    });
  });

  group('TaskDraft', () {
    const TaskDraft draft = TaskDraft(draftId: 'd1', title: 'Check App Store');

    test('validity follows the title', () {
      expect(draft.isValid, isTrue);
      expect(draft.copyWith(title: '  ').isValid, isFalse);
    });

    test('clearing the date clears the time and the reminder with it', () {
      final TaskDraft dated = draft.copyWith(
        date: const LocalDate(2026, 9, 21),
        time: const LocalTimeOfDay.hm(15, 0),
        hasReminder: true,
      );
      expect(dated.isAllDay, isFalse);

      final TaskDraft cleared = dated.copyWith(clearDate: true);
      expect(cleared.date, isNull);
      expect(
        cleared.time,
        isNull,
        reason: 'a time with no date has nothing to attach to',
      );

      expect(dated.copyWith(clearTime: true).time, isNull);
      expect(dated.copyWith(clearTime: true).date, isNotNull);
    });

    test('copyWith keeps the draft id, the source and the transcript', () {
      const TaskDraft seeded = TaskDraft(
        draftId: 'd1',
        title: 'x',
        source: TaskSource.voice,
        sourceTranscript: 'the whole sentence',
      );
      final TaskDraft edited = seeded.copyWith(title: 'y');
      expect(edited.draftId, 'd1');
      expect(edited.source, TaskSource.voice);
      expect(edited.sourceTranscript, 'the whole sentence');
      expect(
        edited.copyWith(lowConfidenceDate: true).lowConfidenceDate,
        isTrue,
      );
    });

    test('equality, hashCode and toString', () {
      expect(draft, const TaskDraft(draftId: 'd1', title: 'Check App Store'));
      expect(
        draft.hashCode,
        const TaskDraft(draftId: 'd1', title: 'Check App Store').hashCode,
      );
      expect(draft == draft.copyWith(title: 'other'), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(draft == 'd1', isFalse);
      expect(draft.toString(), contains('someday'));
    });
  });
}
