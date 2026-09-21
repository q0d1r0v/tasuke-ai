import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/features/tasks/data/drift_task_repository.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

import 'database_test_kit.dart';

/// An instant on [kToday] minus [back] days, at 12:00 local — far enough from
/// both midnights that the local-day bucketing cannot be an artefact of the
/// machine's timezone.
DateTime completionAt(int back) => DateTime(
  kTestNowLocal.year,
  kTestNowLocal.month,
  kTestNowLocal.day - back,
  12,
).toUtc();

TaskStatsRows rowsWith(
  List<int> daysBack, {
  int pending = 0,
  int? completedTotal,
}) => TaskStatsRows(
  pending: pending,
  completedTotal: completedTotal ?? daysBack.length,
  recentCompletions: daysBack.map(completionAt).toList(growable: false),
);

void main() {
  group('toStats — the pure arithmetic', () {
    test('an empty database is all zeros with a seven-slot chart', () {
      final TaskStats stats = DriftTaskRepository.toStats(
        TaskStatsRows.empty,
        today: kToday,
      );

      expect(stats.pending, 0);
      expect(stats.completedTotal, 0);
      expect(stats.completedThisWeek, 0);
      expect(stats.streakDays, 0);
      expect(stats.completionsByDay, <int>[0, 0, 0, 0, 0, 0, 0]);
    });

    test('completionsByDay is oldest-first and ends today', () {
      // One completion six days ago, two today.
      final TaskStats stats = DriftTaskRepository.toStats(
        rowsWith(<int>[6, 0, 0]),
        today: kToday,
      );

      expect(stats.completionsByDay, <int>[1, 0, 0, 0, 0, 0, 2]);
    });

    test(
      'a completion seven days ago is off the chart but still in the total',
      () {
        final TaskStats stats = DriftTaskRepository.toStats(
          rowsWith(<int>[7, 0]),
          today: kToday,
        );

        expect(stats.completionsByDay, <int>[0, 0, 0, 0, 0, 0, 1]);
        expect(stats.completedThisWeek, 1);
        expect(stats.completedTotal, 2);
      },
    );

    test('completedThisWeek is exactly the sum of the bars above it', () {
      final TaskStats stats = DriftTaskRepository.toStats(
        rowsWith(<int>[0, 1, 1, 3, 6, 6, 9, 40]),
        today: kToday,
      );

      int sum = 0;
      for (final int count in stats.completionsByDay) {
        sum += count;
      }
      expect(stats.completedThisWeek, sum);
      // The 9- and 40-day-old ones are outside the week but inside the total.
      expect(stats.completedThisWeek, 6);
      expect(stats.completedTotal, 8);
    });

    test('a streak counts back from today', () {
      expect(
        DriftTaskRepository.toStats(
          rowsWith(<int>[0, 1, 2, 3]),
          today: kToday,
        ).streakDays,
        4,
      );
    });

    test('a gap ends the streak', () {
      expect(
        DriftTaskRepository.toStats(
          // Nothing two days ago.
          rowsWith(<int>[0, 1, 3, 4, 5]),
          today: kToday,
        ).streakDays,
        2,
      );
    });

    test('today is a grace day: an unfinished morning keeps the streak', () {
      // ⚠️ The behaviour worth pinning. Counting strictly from today would show
      // a thirty-day streak as 0 every morning until the first task is ticked.
      expect(
        DriftTaskRepository.toStats(
          rowsWith(<int>[1, 2, 3]),
          today: kToday,
        ).streakDays,
        3,
      );
    });

    test('the grace day does not resurrect a streak that already broke', () {
      expect(
        DriftTaskRepository.toStats(
          // Nothing today and nothing yesterday.
          rowsWith(<int>[2, 3, 4]),
          today: kToday,
        ).streakDays,
        0,
      );
    });

    test('several completions on one day count as one streak day', () {
      expect(
        DriftTaskRepository.toStats(
          rowsWith(<int>[0, 0, 0, 1, 1]),
          today: kToday,
        ).streakDays,
        2,
      );
    });

    test('the streak is bounded by the query window', () {
      expect(
        DriftTaskRepository.toStats(
          rowsWith(<int>[for (int back = 0; back <= 500; back++) back]),
          today: kToday,
        ).streakDays,
        kStatsWindowDays,
      );
    });
  });

  group('watchStats — end to end', () {
    late AppDatabase db;
    late DriftTaskRepository repository;
    final MutableClock clock = MutableClock(kTestNowLocal);

    setUp(() {
      clock.instant = kTestNowLocal;
      db = openTestDatabase(clock: clock);
      repository = DriftTaskRepository(dao: db.tasksDao, clock: clock);
    });

    tearDown(() => db.close());

    Future<Task> add(String title) => repository.create(
      TaskDraft(draftId: title, title: title),
      allDayReminderMinute: 540,
    );

    Future<void> completeOn(Task task, int daysBack) async {
      clock.instant = kTestNowLocal.subtract(Duration(days: daysBack));
      await repository.setCompleted(task.id, completed: true);
      clock.instant = kTestNowLocal;
    }

    test('counts what is actually in the database', () async {
      final Task a = await add('a');
      final Task b = await add('b');
      await add('c');

      await completeOn(a, 0);
      await completeOn(b, 1);

      final TaskStats stats = await repository.watchStats(kToday).first;

      expect(stats.pending, 1);
      expect(stats.completedTotal, 2);
      expect(stats.completedThisWeek, 2);
      expect(stats.streakDays, 2);
      expect(stats.completionsByDay, <int>[0, 0, 0, 0, 0, 1, 1]);
    });

    test(
      're-emits when a task is completed and when it is un-completed',
      () async {
        final Task a = await add('a');
        final Future<List<TaskStats>> collected = repository
            .watchStats(kToday)
            .take(3)
            .toList();

        await pumpEventQueue();
        await repository.setCompleted(a.id, completed: true);
        await pumpEventQueue();
        await repository.setCompleted(a.id, completed: false);

        final List<TaskStats> emissions = await collected;
        expect(emissions.map((TaskStats s) => s.completedTotal).toList(), <int>[
          0,
          1,
          0,
        ]);
        expect(emissions.map((TaskStats s) => s.pending).toList(), <int>[
          1,
          0,
          1,
        ]);
      },
    );

    test('re-emits on an edit that changes no count', () async {
      // ⚠️ This is what the checksum ticker buys. A stats stream keyed on
      // `COUNT(*)` alone would go silent here, and the Stats screen would sit
      // on stale numbers until it was rebuilt.
      final Task a = await add('a');
      final Future<List<TaskStats>> collected = repository
          .watchStats(kToday)
          .take(2)
          .toList();

      await pumpEventQueue();
      clock.advance(const Duration(minutes: 1));
      await repository.update(a.copyWith(title: 'a renamed'));

      expect((await collected).length, 2);
    });

    test('deleting everything empties the stats', () async {
      final Task a = await add('a');
      await completeOn(a, 0);

      await repository.deleteAll();

      final TaskStats stats = await repository.watchStats(kToday).first;
      expect(stats.pending, 0);
      expect(stats.completedTotal, 0);
      expect(stats.streakDays, 0);
      expect(stats.completionsByDay, <int>[0, 0, 0, 0, 0, 0, 0]);
    });

    test('a completion older than the window is outside the totals', () async {
      final Task old = await add('old');
      await completeOn(old, kStatsWindowDays + 30);

      final TaskStats stats = await repository.watchStats(kToday).first;

      // `completedTotal` is an unbounded COUNT, so it still sees it …
      expect(stats.completedTotal, 1);
      // … but the windowed detail does not.
      expect(stats.streakDays, 0);
      expect(stats.completionsByDay, <int>[0, 0, 0, 0, 0, 0, 0]);
    });
  });
}
