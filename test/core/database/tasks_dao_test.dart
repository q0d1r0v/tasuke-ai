import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'database_test_kit.dart';

void main() {
  late AppDatabase db;
  late TasksDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.tasksDao;
  });

  tearDown(() => db.close());

  List<String> idsOf(List<TaskRow> rows) =>
      rows.map((TaskRow r) => r.id).toList();

  group('watchToday', () {
    test(
      'includes undated, overdue and due-today; excludes future and done',
      () async {
        await dao.insertDrafts(<TasksCompanion>[
          taskRow('undated'),
          taskRow('overdue', dueDate: kToday.addDays(-3)),
          taskRow('today', dueDate: kToday),
          taskRow('tomorrow', dueDate: kToday.addDays(1)),
          taskRow(
            'done',
            dueDate: kToday,
            completed: true,
            completedAt: kTestNowLocal.toUtc(),
          ),
        ]);

        final List<TaskRow> rows = await dao.watchToday(kToday).first;

        // Overdue first (earlier date), then today, then the undated tail.
        expect(idsOf(rows), <String>['overdue', 'today', 'undated']);
      },
    );

    test('re-emits on every write, not just on the first read', () async {
      final List<List<String>> seen = <List<String>>[];
      final StreamSubscription<List<TaskRow>> sub = dao
          .watchToday(kToday)
          .listen((List<TaskRow> rows) => seen.add(idsOf(rows)));
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await dao.insertTask(taskRow('a', dueDate: kToday));
      await pumpEventQueue();
      await dao.setCompleted(
        'a',
        completed: true,
        nowUtc: kTestNowLocal.toUtc(),
      );
      await pumpEventQueue();

      // Appears on insert and disappears on completion — a list that only
      // refreshed when it was rebuilt would show a ticked task until the user
      // navigated away and back.
      expect(seen, <List<String>>[
        <String>[],
        <String>['a'],
        <String>[],
      ]);
    });
  });

  group('the today/upcoming boundary', () {
    // ⚠️ The boundary is a *date* comparison, so a task due today is on Today
    // whether it is due at 00:00 or at 23:59, and a task due tomorrow is on
    // Upcoming even at 00:00. A boundary computed from instants would move
    // these two rows around as the clock ticked past midnight in some other
    // timezone.
    setUp(() async {
      await dao.insertDrafts(<TasksCompanion>[
        taskRow('today-2359', dueDate: kToday, dueMinuteOfDay: 23 * 60 + 59),
        taskRow('tomorrow-0000', dueDate: kToday.addDays(1), dueMinuteOfDay: 0),
      ]);
    });

    test('23:59 today is on Today, not Upcoming', () async {
      expect(idsOf(await dao.watchToday(kToday).first), contains('today-2359'));
      expect(
        idsOf(await dao.watchUpcoming(kToday).first),
        isNot(contains('today-2359')),
      );
    });

    test('00:00 tomorrow is on Upcoming, not Today', () async {
      expect(
        idsOf(await dao.watchUpcoming(kToday).first),
        contains('tomorrow-0000'),
      );
      expect(
        idsOf(await dao.watchToday(kToday).first),
        isNot(contains('tomorrow-0000')),
      );
    });
  });

  group('ordering', () {
    test(
      'dated before undated, all-day before timed, then sort_order',
      () async {
        await dao.insertDrafts(<TasksCompanion>[
          taskRow('undated-a', sortOrder: 0),
          taskRow(
            'd2-timed-9',
            dueDate: kToday.addDays(2),
            dueMinuteOfDay: 540,
          ),
          taskRow('d1-timed-18', dueDate: kToday, dueMinuteOfDay: 1080),
          taskRow('d1-allday-b', dueDate: kToday, sortOrder: 1),
          taskRow('d1-allday-a', dueDate: kToday, sortOrder: 0),
          taskRow('d1-timed-9', dueDate: kToday, dueMinuteOfDay: 540),
        ]);

        expect(idsOf(await dao.watchToday(kToday).first), <String>[
          'd1-allday-a',
          'd1-allday-b',
          'd1-timed-9',
          'd1-timed-18',
          'undated-a',
        ]);
      },
    );

    test('completed is newest-completion-first', () async {
      final DateTime base = kTestNowLocal.toUtc();
      await dao.insertDrafts(<TasksCompanion>[
        taskRow(
          'old',
          completed: true,
          completedAt: base.subtract(const Duration(days: 2)),
        ),
        taskRow('new', completed: true, completedAt: base),
        taskRow(
          'middle',
          completed: true,
          completedAt: base.subtract(const Duration(hours: 5)),
        ),
      ]);

      expect(idsOf(await dao.watchCompleted().first), <String>[
        'new',
        'middle',
        'old',
      ]);
    });
  });

  group('watchSearch', () {
    setUp(() async {
      await dao.insertDrafts(<TasksCompanion>[
        taskRow('cafe', title: 'Book a table at the Café'),
        taskRow('milk', title: 'Buy MILK'),
        taskRow('percent', title: 'Ship the 100% build'),
        taskRow(
          'done',
          title: 'Milk the schedule',
          completed: true,
          completedAt: kTestNowLocal.toUtc(),
        ),
      ]);
    });

    test('is case-insensitive', () async {
      expect(
        idsOf(await dao.watchSearch(foldForSearch('milk')).first),
        <String>['milk', 'done'],
      );
    });

    test('matches across a diacritic', () async {
      expect(
        idsOf(await dao.watchSearch(foldForSearch('cafe')).first),
        <String>['cafe'],
      );
      expect(
        idsOf(await dao.watchSearch(foldForSearch('CAFÉ')).first),
        <String>['cafe'],
      );
    });

    test('open tasks rank above completed ones', () async {
      final List<TaskRow> rows = await dao
          .watchSearch(foldForSearch('milk'))
          .first;
      expect(rows.first.id, 'milk');
      expect(rows.last.id, 'done');
    });

    test('a needle of only LIKE metacharacters matches nothing, not everything', () async {
      // Folding strips `%`, so the needle is empty and the DAO short-circuits.
      // Without both halves of that, the pattern would be '%%%' and every task
      // in the database would come back.
      expect(await dao.watchSearch(foldForSearch('%')).first, isEmpty);
    });

    test('finds a title that contains a literal percent sign', () async {
      // '100% build' and 'the 100% build' both fold to the same wildcard-free
      // text, so the stored title is reachable by the words around the `%`.
      expect(idsOf(await dao.watchSearch(foldForSearch('100')).first), <String>[
        'percent',
      ]);
      expect(
        idsOf(await dao.watchSearch(foldForSearch('100% build')).first),
        <String>['percent'],
      );
    });
  });

  group('reminders', () {
    setUp(() async {
      await dao.insertDrafts(<TasksCompanion>[
        taskRow(
          'past',
          reminderEnabled: true,
          reminderAtLocal: LocalDateTime.parseIso('2026-03-11T08:00'),
        ),
        taskRow(
          'soon',
          reminderEnabled: true,
          reminderAtLocal: LocalDateTime.parseIso('2026-03-11T15:00'),
        ),
        taskRow(
          'later',
          reminderEnabled: true,
          reminderAtLocal: LocalDateTime.parseIso('2026-04-02T09:00'),
        ),
        taskRow(
          'disabled',
          reminderAtLocal: LocalDateTime.parseIso('2026-03-11T16:00'),
        ),
        taskRow(
          'finished',
          reminderEnabled: true,
          reminderAtLocal: LocalDateTime.parseIso('2026-03-11T17:00'),
          completed: true,
          completedAt: kTestNowLocal.toUtc(),
        ),
      ]);
    });

    test(
      'dueReminders returns only future, enabled, open ones in order',
      () async {
        expect(idsOf(await dao.dueReminders('2026-03-11T10:00')), <String>[
          'soon',
          'later',
        ]);
      },
    );

    test('dueReminders honours its window', () async {
      expect(
        idsOf(await dao.dueReminders('2026-03-11T10:00', limit: 1)),
        <String>['soon'],
      );
    });

    test('the default window is the platform cap, not an arbitrary number', () {
      expect(TasksDao.kReminderWindow, 64);
    });

    test('allSchedulable is the same set with no window', () async {
      expect(idsOf(await dao.allSchedulable('2026-03-11T10:00')), <String>[
        'soon',
        'later',
      ]);
    });
  });

  group('nextNotificationId', () {
    test('increments and persists', () async {
      final DateTime now = kTestNowLocal.toUtc();
      expect(await dao.nextNotificationId(nowUtc: now), 1);
      expect(await dao.nextNotificationId(nowUtc: now), 2);
      expect(await dao.nextNotificationId(nowUtc: now), 3);
    });

    test('never hands out the same id twice under concurrency', () async {
      final DateTime now = kTestNowLocal.toUtc();
      final List<int> ids = await Future.wait<int>(<Future<int>>[
        for (int i = 0; i < 25; i++) dao.nextNotificationId(nowUtc: now),
      ]);
      expect(ids.toSet().length, 25);
    });

    test('stays inside the 32-bit signed range Android accepts', () async {
      final DateTime now = kTestNowLocal.toUtc();
      await dao.settingsEntries.insertOne(
        SettingsEntriesCompanion(
          key: const Value<String>(SettingKeys.notificationIdCounter),
          value: Value<String>('${TasksDao.kMaxNotificationId - 1}'),
          updatedAtUtcMs: Value<DateTime>(now),
        ),
        mode: InsertMode.insertOrReplace,
      );

      expect(
        await dao.nextNotificationId(nowUtc: now),
        TasksDao.kMaxNotificationId,
      );
      // And then wraps rather than overflowing a Java int.
      expect(await dao.nextNotificationId(nowUtc: now), 1);
    });

    test('survives a corrupt counter value instead of throwing', () async {
      final DateTime now = kTestNowLocal.toUtc();
      await dao.settingsEntries.insertOne(
        SettingsEntriesCompanion(
          key: const Value<String>(SettingKeys.notificationIdCounter),
          value: const Value<String>('not a number'),
          updatedAtUtcMs: Value<DateTime>(now),
        ),
        mode: InsertMode.insertOrReplace,
      );

      expect(await dao.nextNotificationId(nowUtc: now), 1);
    });
  });

  group('writes', () {
    test('inserts 500 drafts in a single transaction', () async {
      final List<TasksCompanion> rows = <TasksCompanion>[
        for (int i = 0; i < 500; i++)
          taskRow(
            'bulk-$i',
            title: 'Bulk task $i',
            dueDate: kToday.addDays(i % 7),
            sortOrder: i,
          ),
      ];

      await dao.insertDrafts(rows);

      final int count = await db
          .customSelect('SELECT COUNT(*) AS c FROM tasks')
          .getSingle()
          .then((QueryRow row) => row.read<int>('c'));
      expect(count, 500);
    });

    test('a failing bulk insert leaves nothing behind', () async {
      await dao.insertTask(taskRow('clash'));

      // Same primary key twice: the second row of the batch fails, and the
      // point of the transaction is that the first one does not survive it.
      await expectLater(
        dao.insertDrafts(<TasksCompanion>[taskRow('fresh'), taskRow('clash')]),
        throwsA(isA<Object>()),
      );

      expect(await dao.findById('fresh'), isNull);
    });

    test('setCompleted stamps and then clears completed_at', () async {
      final DateTime now = kTestNowLocal.toUtc();
      await dao.insertTask(taskRow('a'));

      await dao.setCompleted('a', completed: true, nowUtc: now);
      TaskRow? row = await dao.findById('a');
      expect(row!.completed, isTrue);
      expect(row.completedAtUtcMs, now);

      await dao.setCompleted('a', completed: false, nowUtc: now);
      row = await dao.findById('a');
      expect(row!.completed, isFalse);
      expect(row.completedAtUtcMs, isNull);
    });

    test(
      'deleteAll empties tasks but keeps the notification counter',
      () async {
        final DateTime now = kTestNowLocal.toUtc();
        await dao.insertTask(taskRow('a'));
        await dao.nextNotificationId(nowUtc: now);
        await dao.nextNotificationId(nowUtc: now);

        await dao.deleteAll();

        expect(await dao.watchToday(kToday).first, isEmpty);
        // Still 3, not 1 — the OS may hold alarms for ids 1 and 2.
        expect(await dao.nextNotificationId(nowUtc: now), 3);
      },
    );

    test('watchById emits null after a delete', () async {
      await dao.insertTask(taskRow('a'));
      expect((await dao.watchById('a').first)?.id, 'a');

      await dao.deleteTask('a');
      expect(await dao.watchById('a').first, isNull);
    });
  });

  group('the stored shape', () {
    test(
      'a due date is TEXT and a created stamp is INTEGER milliseconds',
      () async {
        await dao.insertTask(
          taskRow(
            'a',
            dueDate: const LocalDate(2026, 3, 11),
            createdAt: DateTime.utc(2026, 3, 11, 10, 0, 0, 123),
          ),
        );

        final QueryRow raw = await db
            .customSelect(
              'SELECT due_date, created_at_utc_ms, typeof(due_date) AS dt, '
              'typeof(created_at_utc_ms) AS ct FROM tasks',
            )
            .getSingle();

        expect(raw.read<String>('dt'), 'text');
        expect(raw.read<String>('due_date'), '2026-03-11');
        expect(raw.read<String>('ct'), 'integer');
        expect(raw.read<int>('created_at_utc_ms') % 1000, 123);
      },
    );
  });
}
