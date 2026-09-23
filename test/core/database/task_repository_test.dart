import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/data/drift_task_repository.dart';
import 'package:tasuke_ai/features/tasks/data/task_mapper.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

import 'database_test_kit.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository repository;
  final MutableClock clock = MutableClock(kTestNowLocal);

  setUp(() {
    clock.instant = kTestNowLocal;
    db = openTestDatabase(clock: clock);
    repository = DriftTaskRepository(dao: db.tasksDao, clock: clock);
  });

  tearDown(() => db.close());

  TaskDraft draft(
    String id, {
    String title = 'Task',
    LocalDate? date,
    LocalTimeOfDay? time,
    bool hasReminder = false,
    String? transcript,
  }) => TaskDraft(
    draftId: id,
    title: title,
    date: date,
    time: time,
    hasReminder: hasReminder,
    sourceTranscript: transcript,
  );

  group('saveDrafts', () {
    test(
      'writes the whole capture and returns it in Confirm-card order',
      () async {
        final List<Task> saved = await repository.saveDrafts(
          <TaskDraft>[
            draft('1', title: 'Call the dentist', date: kToday),
            draft('2', title: 'Buy milk'),
            draft(
              '3',
              title: 'Ship the build',
              date: kToday.addDays(1),
              time: const LocalTimeOfDay.hm(15, 0),
            ),
          ],
          captureId: 'capture-a',
          allDayReminderMinute: 9 * 60,
        );

        expect(saved.map((Task t) => t.title).toList(), <String>[
          'Call the dentist',
          'Buy milk',
          'Ship the build',
        ]);
        expect(saved.map((Task t) => t.sortOrder).toList(), <int>[0, 1, 2]);
        expect(saved.every((Task t) => t.captureId == 'capture-a'), isTrue);
        expect(saved.map((Task t) => t.id).toSet().length, 3);

        // And they are actually in the database, not just returned.
        expect((await repository.watchToday(kToday).first).length, 2);
      },
    );

    test('an empty capture writes nothing', () async {
      expect(
        await repository.saveDrafts(
          const <TaskDraft>[],
          captureId: 'capture-a',
          allDayReminderMinute: 540,
        ),
        isEmpty,
      );
    });

    test('normalises the title and keeps the fold in step', () async {
      final List<Task> saved = await repository.saveDrafts(
        <TaskDraft>[draft('1', title: '  Book   a table at the Café  ')],
        captureId: 'c',
        allDayReminderMinute: 540,
      );

      expect(saved.single.title, 'Book a table at the Café');
      // Searchable by the folded form, which only works if the fold was
      // recomputed from the *normalised* title.
      expect(
        (await repository.watchSearch('cafe').first).single.id,
        saved.single.id,
      );
    });

    test(
      'keeps the transcript on the row and out of everything else',
      () async {
        final List<Task> saved = await repository.saveDrafts(
          <TaskDraft>[
            draft('1', title: 'Call Mum', transcript: 'remind me to call mum'),
          ],
          captureId: 'c',
          allDayReminderMinute: 540,
        );

        expect(saved.single.sourceTranscript, 'remind me to call mum');
        expect(await repository.findById(saved.single.id), saved.single);
      },
    );
  });

  group('reminder resolution', () {
    Future<Task> save(TaskDraft d, {int allDayMinute = 9 * 60}) async {
      final List<Task> saved = await repository.saveDrafts(
        <TaskDraft>[d],
        captureId: 'c',
        allDayReminderMinute: allDayMinute,
      );
      return saved.single;
    }

    test('a timed task fires at its own time', () async {
      final Task task = await save(
        draft(
          '1',
          date: kToday,
          time: const LocalTimeOfDay.hm(15, 0),
          hasReminder: true,
        ),
      );

      expect(task.reminder.enabled, isTrue);
      expect(task.reminder.at, LocalDateTime.parseIso('2026-03-11T15:00'));
    });

    test('an all-day task fires at the configured all-day minute', () async {
      final Task task = await save(
        draft('1', date: kToday.addDays(1), hasReminder: true),
        allDayMinute: 7 * 60 + 30,
      );

      expect(task.reminder.at, LocalDateTime.parseIso('2026-03-12T07:30'));
    });

    test('an all-day task due today, saved after its all-day minute, still '
        'rings today', () async {
      // ⚠️ "Remind me to buy milk today" at 10:00 used to resolve to 07:30 —
      // already past, so the planner skipped it and nothing ever rang.
      final Task task = await save(
        draft('1', date: kToday, hasReminder: true),
        allDayMinute: 7 * 60 + 30,
      );

      expect(task.reminder.at, LocalDateTime.parseIso('2026-03-11T10:15'));
    });

    test('only all-day tasks due today are moved forward', () {
      final LocalDateTime now = LocalDateTime.parseIso('2026-03-11T10:07');
      LocalDateTime resolve(TaskDue due) => TaskMapper.resolveReminderAt(
        due,
        allDayReminderMinute: 540,
        now: now,
      );

      expect(
        resolve(TaskDue(date: kToday)),
        LocalDateTime.parseIso('2026-03-11T10:15'),
      );
      // A time the user said is theirs, even when it has passed.
      expect(
        resolve(TaskDue(date: kToday, time: const LocalTimeOfDay.hm(8, 0))),
        LocalDateTime.parseIso('2026-03-11T08:00'),
      );
      // An overdue task is not revived as a fresh reminder.
      expect(
        resolve(TaskDue(date: kToday.addDays(-1))),
        LocalDateTime.parseIso('2026-03-10T09:00'),
      );
      // Late in the evening it stays on the due day rather than midnight.
      expect(
        TaskMapper.resolveReminderAt(
          TaskDue(date: kToday),
          allDayReminderMinute: 540,
          now: LocalDateTime.parseIso('2026-03-11T23:50'),
        ),
        LocalDateTime.parseIso('2026-03-11T23:59'),
      );
    });

    group('a moved-forward reminder leaves the sweep room to arm it', () {
      // ⚠️ It used to be the NEXT quarter hour, however close. Saved at
      // 14:14:50 it rang "at 14:15": ten seconds away, while the sweep that
      // arms it waits behind the save's permission prompts. Back from the
      // Alarms & reminders page at 14:15:10, the sweep saw a time already
      // past and the reminder never rang.
      LocalDateTime resolveAt(String now) => TaskMapper.resolveReminderAt(
        TaskDue(date: kToday),
        allDayReminderMinute: 540,
        now: LocalDateTime.parseIso(now),
      );

      test('one minute short of a quarter hour skips to the next one', () {
        expect(
          resolveAt('2026-03-11T14:14'),
          LocalDateTime.parseIso('2026-03-11T14:30'),
        );
      });

      test('exactly five minutes short still takes that quarter hour', () {
        expect(
          resolveAt('2026-03-11T14:10'),
          LocalDateTime.parseIso('2026-03-11T14:15'),
        );
        expect(
          resolveAt('2026-03-11T14:11'),
          LocalDateTime.parseIso('2026-03-11T14:30'),
        );
      });

      test('on a quarter hour it is the next one, not now', () {
        expect(
          resolveAt('2026-03-11T14:15'),
          LocalDateTime.parseIso('2026-03-11T14:30'),
        );
      });

      test('the 23:59 cap still holds inside the last lead', () {
        expect(
          resolveAt('2026-03-11T23:44'),
          LocalDateTime.parseIso('2026-03-11T23:59'),
        );
        expect(
          resolveAt('2026-03-11T23:57'),
          LocalDateTime.parseIso('2026-03-11T23:59'),
        );
      });

      test('through a real save, seconds before the quarter hour', () async {
        clock.instant = DateTime(2026, 3, 11, 14, 14, 50);

        final Task task = await save(
          draft('1', date: kToday, hasReminder: true),
        );

        expect(task.reminder.at, LocalDateTime.parseIso('2026-03-11T14:30'));
      });
    });

    test(
      'a reminder on an undated task is dropped, not stored dangling',
      () async {
        final Task task = await save(draft('1', hasReminder: true));

        expect(task.reminder.enabled, isFalse);
        expect(task.reminder.at, isNull);
        expect(task.reminder.notificationId, isNull);
        // And the orphan sweep never sees it.
        expect(
          await repository.allSchedulable(
            LocalDateTime.parseIso('2026-01-01T00:00'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'a notification id is issued only to tasks that will be scheduled',
      () async {
        final List<Task> saved = await repository.saveDrafts(
          <TaskDraft>[
            draft('1', date: kToday, hasReminder: true),
            draft('2', date: kToday),
            draft('3', date: kToday.addDays(1), hasReminder: true),
          ],
          captureId: 'c',
          allDayReminderMinute: 540,
        );

        expect(saved[0].reminder.notificationId, 1);
        expect(saved[1].reminder.notificationId, isNull);
        expect(saved[2].reminder.notificationId, 2);
      },
    );

    test('the lead time rolls the reminder back across midnight', () {
      // Pure arithmetic, deliberately: the trap is clamping the minute at zero
      // instead of moving the date.
      expect(
        TaskMapper.resolveReminderAt(
          TaskDue(
            date: const LocalDate(2026, 3, 11),
            time: const LocalTimeOfDay.hm(0, 15),
          ),
          allDayReminderMinute: 540,
          leadMinutes: 30,
        ),
        LocalDateTime.parseIso('2026-03-10T23:45'),
      );
    });

    test('saveDrafts does not schedule anything itself', () async {
      // The repository's contract stops at the row. This asserts the row is
      // complete enough for the scheduler to do its job from a cold start.
      final Task task = await save(
        draft(
          '1',
          date: kToday.addDays(2),
          time: const LocalTimeOfDay.hm(8, 0),
          hasReminder: true,
        ),
      );

      final List<Task> pending = await repository.pendingReminders(
        LocalDateTime.fromLocal(kTestNowLocal),
      );
      expect(pending.single.id, task.id);
      expect(pending.single.reminder.notificationId, isNotNull);
    });
  });

  group('lists', () {
    setUp(() async {
      await repository.saveDrafts(
        <TaskDraft>[
          draft('a', title: 'Overdue', date: kToday.addDays(-2)),
          draft('b', title: 'Today'),
          draft('c', title: 'Tomorrow', date: kToday.addDays(1)),
          draft('d', title: 'Friday', date: kToday.addDays(2)),
          draft('e', title: 'Next week', date: kToday.addDays(9)),
          draft('f', title: 'Someday'),
        ],
        captureId: 'c',
        allDayReminderMinute: 540,
      );
    });

    test('upcoming is grouped and labelled in Dart, not in SQL', () async {
      final List<TaskGroup> groups = await repository
          .watchUpcoming(kToday)
          .first;

      expect(groups.map((TaskGroup g) => g.label).toList(), <TaskGroupLabel>[
        TaskGroupLabel.tomorrow,
        TaskGroupLabel.weekday,
        TaskGroupLabel.nextWeek,
      ]);
      expect(groups.first.tasks.single.title, 'Tomorrow');
    });

    test('someday is the undated tail', () async {
      final List<Task> someday = await repository.watchSomeday().first;
      expect(someday.map((Task t) => t.title).toSet(), <String>{
        'Today',
        'Someday',
      });
    });

    test('completed groups by the day it was finished', () async {
      final List<Task> today = await repository.watchToday(kToday).first;
      await repository.setCompleted(today.first.id, completed: true);

      clock.instant = kTestNowLocal.subtract(const Duration(days: 2));
      await repository.setCompleted(today.last.id, completed: true);

      final List<TaskGroup> groups = await repository
          .watchCompleted(kToday)
          .first;

      expect(groups.length, 2);
      expect(groups.first.date, kToday);
      expect(groups.last.date, kToday.addDays(-2));
      expect(
        groups.every((TaskGroup g) => g.label == TaskGroupLabel.completedOn),
        isTrue,
      );
    });
  });

  group('mutations', () {
    test('create writes a single manual task with no capture', () async {
      final Task task = await repository.create(
        draft('1', title: 'Manual task', date: kToday),
        allDayReminderMinute: 540,
      );

      expect(task.captureId, isNull);
      expect(await repository.findById(task.id), task);
    });

    test('update stamps updatedAt and keeps createdAt', () async {
      final Task task = await repository.create(
        draft('1', title: 'Original'),
        allDayReminderMinute: 540,
      );

      clock.advance(const Duration(hours: 3));
      final Task updated = await repository.update(
        task.copyWith(
          title: 'Renamed',
          // A caller trying to pin updatedAt is ignored on purpose.
          updatedAt: DateTime.utc(2000),
        ),
      );

      expect(updated.title, 'Renamed');
      expect(updated.createdAt, task.createdAt);
      expect(updated.updatedAt, clock.nowUtc());
      expect((await repository.findById(task.id))!.title, 'Renamed');
    });

    test(
      'a reminder switched on later gets an id, so it can be scheduled',
      () async {
        // ⚠️ The bug this pins: a task saved without a reminder has no
        // notification id, and the planner silently skips a reminder without
        // one. Turning the switch on in Task details showed "on" and scheduled
        // nothing, ever.
        final Task task = await repository.create(
          draft('1', title: 'Call Anna', date: kToday),
          allDayReminderMinute: 540,
        );
        expect(task.reminder.notificationId, isNull);

        final Task on = await repository.update(
          task.copyWith(
            reminder: task.reminder.copyWith(
              enabled: true,
              at: LocalDateTime(kToday, const LocalTimeOfDay.hm(18, 11)),
            ),
          ),
        );

        expect(on.reminder.notificationId, isNotNull);
        expect(
          (await repository.findById(task.id))!.reminder.notificationId,
          on.reminder.notificationId,
        );
      },
    );

    test('an id is minted once and kept across later edits', () async {
      final Task task = await repository.create(
        draft('1', title: 'Call Anna', date: kToday, hasReminder: true),
        allDayReminderMinute: 540,
      );
      final int? id = task.reminder.notificationId;
      expect(id, isNotNull);

      final Task renamed = await repository.update(
        task.copyWith(title: 'Call Anna back'),
      );

      // Same id means the OS alarm is replaced, not joined by a second one.
      expect(renamed.reminder.notificationId, id);
    });

    test('a reminder left off is not given an id', () async {
      final Task task = await repository.create(
        draft('1', title: 'Someday'),
        allDayReminderMinute: 540,
      );

      final Task renamed = await repository.update(
        task.copyWith(title: 'Someday, maybe'),
      );

      expect(renamed.reminder.notificationId, isNull);
    });

    test('renaming keeps the task findable under its new title', () async {
      final Task task = await repository.create(
        draft('1', title: 'Original'),
        allDayReminderMinute: 540,
      );

      await repository.update(task.copyWith(title: 'Café run'));

      expect(await repository.watchSearch('original').first, isEmpty);
      expect((await repository.watchSearch('cafe').first).single.id, task.id);
    });

    test('setCompleted round-trips through completed_at', () async {
      final Task task = await repository.create(
        draft('1'),
        allDayReminderMinute: 540,
      );

      await repository.setCompleted(task.id, completed: true);
      expect((await repository.findById(task.id))!.completedAt, clock.nowUtc());

      await repository.setCompleted(task.id, completed: false);
      expect((await repository.findById(task.id))!.completedAt, isNull);
    });

    test('delete removes one, deleteAll removes the rest', () async {
      final Task first = await repository.create(
        draft('1'),
        allDayReminderMinute: 540,
      );
      await repository.create(draft('2'), allDayReminderMinute: 540);

      await repository.delete(first.id);
      expect(await repository.findById(first.id), isNull);
      expect((await repository.watchToday(kToday).first).length, 1);

      await repository.deleteAll();
      expect(await repository.watchToday(kToday).first, isEmpty);
    });

    test('deleteAll leaves the notification counter where it was', () async {
      await repository.create(
        draft('1', date: kToday, hasReminder: true),
        allDayReminderMinute: 540,
      );
      await repository.deleteAll();

      expect(await db.settingsDao.read(SettingKeys.notificationIdCounter), '1');
    });
  });

  group('streams', () {
    test('watchById follows edits and ends at null after a delete', () async {
      final Task task = await repository.create(
        draft('1', title: 'Original'),
        allDayReminderMinute: 540,
      );

      expect((await repository.watchById(task.id).first)!.title, 'Original');
      await repository.update(task.copyWith(title: 'Renamed'));
      expect((await repository.watchById(task.id).first)!.title, 'Renamed');
      await repository.delete(task.id);
      expect(await repository.watchById(task.id).first, isNull);
    });

    test(
      'an empty search query returns nothing rather than everything',
      () async {
        await repository.create(draft('1'), allDayReminderMinute: 540);
        expect(await repository.watchSearch('').first, isEmpty);
        expect(await repository.watchSearch('   ').first, isEmpty);
      },
    );
  });

  group('the mapper round-trip', () {
    test('every field survives a write and a read', () async {
      final Task original = Task(
        id: 'full',
        title: 'Café run',
        notes: 'Table for four',
        due: TaskDue(
          date: const LocalDate(2026, 3, 12),
          time: const LocalTimeOfDay.hm(15, 30),
        ),
        reminder: TaskReminder(
          enabled: true,
          leadMinutes: 15,
          at: LocalDateTime.parseIso('2026-03-12T15:15'),
          notificationId: 42,
        ),
        completed: true,
        completedAt: DateTime.utc(2026, 3, 12, 16, 0, 0, 250),
        createdAt: DateTime.utc(2026, 3, 10, 9),
        updatedAt: DateTime.utc(2026, 3, 11, 9),
        source: TaskSource.voice,
        sourceTranscript: 'book a table for four tomorrow at half three',
        captureId: 'capture-z',
        sortOrder: 7,
      );

      await db.tasksDao.insertTask(TaskMapper.toCompanion(original));

      expect(await repository.findById('full'), original);
    });

    test('an all-day task keeps its distinction from an undated one', () async {
      await db.tasksDao.insertTask(
        TaskMapper.toCompanion(
          Task(
            id: 'allday',
            title: 'All day',
            due: TaskDue(date: kToday),
            createdAt: clock.nowUtc(),
            updatedAt: clock.nowUtc(),
          ),
        ),
      );
      await db.tasksDao.insertTask(
        TaskMapper.toCompanion(
          Task(
            id: 'undated',
            title: 'Undated',
            createdAt: clock.nowUtc(),
            updatedAt: clock.nowUtc(),
          ),
        ),
      );

      final Task allDay = (await repository.findById('allday'))!;
      final Task undated = (await repository.findById('undated'))!;

      expect(allDay.due, isNotNull);
      expect(allDay.isAllDay, isTrue);
      expect(undated.due, isNull);
      expect(undated.isAllDay, isTrue);
      expect(allDay.hasDate, isTrue);
      expect(undated.hasDate, isFalse);
    });
  });
}
