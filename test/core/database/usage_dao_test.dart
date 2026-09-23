import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/usage_dao.dart';
import 'package:tasuke_ai/features/usage/data/drift_usage_repository.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

import 'database_test_kit.dart';

void main() {
  late AppDatabase db;
  late UsageDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.usageDao;
  });

  tearDown(() => db.close());

  group('recordCapture', () {
    test('creates the day on the first capture', () async {
      await dao.recordCapture(kToday.toIso(), taskCount: 3);

      final UsageDayRow? row = await dao.readDay(kToday.toIso());
      expect(row!.captureCount, 1);
      expect(row.taskCount, 3);
    });

    test('accumulates without a read-modify-write', () async {
      await dao.recordCapture(kToday.toIso(), taskCount: 3);
      await dao.recordCapture(kToday.toIso(), taskCount: 1);
      await dao.recordCapture(kToday.toIso(), taskCount: 0);

      final UsageDayRow? row = await dao.readDay(kToday.toIso());
      expect(row!.captureCount, 3);
      expect(row.taskCount, 4);
    });

    test('concurrent captures all land', () async {
      // The increment happens inside SQLite, so twenty overlapping writes
      // cannot lose one to a stale read — which is what the daily free quota
      // depends on being exactly true.
      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < 20; i++)
          dao.recordCapture(kToday.toIso(), taskCount: 1),
      ]);

      final UsageDayRow? row = await dao.readDay(kToday.toIso());
      expect(row!.captureCount, 20);
      expect(row.taskCount, 20);
    });

    test(
      'days are independent, so the quota resets at the day boundary',
      () async {
        await dao.recordCapture(kToday.addDays(-1).toIso(), taskCount: 9);
        await dao.recordCapture(kToday.toIso(), taskCount: 1);

        expect((await dao.readDay(kToday.toIso()))!.captureCount, 1);
        expect(
          (await dao.readDay(kToday.addDays(-1).toIso()))!.captureCount,
          1,
        );
      },
    );
  });

  group('reads', () {
    test('an untouched day is null, not a zero row', () async {
      expect(await dao.readDay(kToday.toIso()), isNull);

      // And reading it did not create one — the quota banner must not write.
      final List<QueryRow> rows = await db
          .customSelect('SELECT * FROM usage_days')
          .get();
      expect(rows, isEmpty);
    });

    test('watchDay re-emits when the day is written', () async {
      final Future<List<UsageDayRow?>> collected = dao
          .watchDay(kToday.toIso())
          .take(2)
          .toList();

      await pumpEventQueue();
      await dao.recordCapture(kToday.toIso(), taskCount: 2);

      final List<UsageDayRow?> emissions = await collected;
      expect(emissions.first, isNull);
      expect(emissions.last!.captureCount, 1);
    });
  });

  group('pruneBefore', () {
    test('drops older days and keeps the boundary day itself', () async {
      for (final int back in <int>[0, 1, 89, 90, 91, 200]) {
        await dao.recordCapture(kToday.addDays(-back).toIso(), taskCount: 1);
      }

      await dao.pruneBefore(kToday.addDays(-90).toIso());

      expect(await dao.readDay(kToday.addDays(-90).toIso()), isNotNull);
      expect(await dao.readDay(kToday.addDays(-89).toIso()), isNotNull);
      expect(await dao.readDay(kToday.addDays(-91).toIso()), isNull);
      expect(await dao.readDay(kToday.addDays(-200).toIso()), isNull);
    });

    test('beforeOpen prunes the window on the next launch', () async {
      // A real file, because the point is that the *second* open of the same
      // database does the pruning — which an in-memory executor cannot show.
      // Two AppDatabase instances over one file is exactly what drift warns
      // about, and exactly what a relaunch does, so the warning is muted here
      // and only here.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );

      final Directory dir = Directory.systemTemp.createTempSync('tasuke_usage');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = File('${dir.path}/tasuke.sqlite');

      final AppDatabase first = AppDatabase.forTesting(
        NativeDatabase(file),
        clock: FixedClock(kTestNowLocal),
      );
      await first.usageDao.recordCapture(
        kToday.addDays(-kUsageRetentionDays - 5).toIso(),
        taskCount: 1,
      );
      await first.usageDao.recordCapture(kToday.toIso(), taskCount: 1);
      await first.close();

      final AppDatabase second = AppDatabase.forTesting(
        NativeDatabase(file),
        clock: FixedClock(kTestNowLocal),
      );
      addTearDown(second.close);

      expect(
        await second.usageDao.readDay(
          kToday.addDays(-kUsageRetentionDays - 5).toIso(),
        ),
        isNull,
      );
      expect(await second.usageDao.readDay(kToday.toIso()), isNotNull);
    });
  });

  group('DriftUsageRepository', () {
    late DriftUsageRepository repository;

    setUp(() => repository = DriftUsageRepository(dao: dao));

    test('an untouched day reads as empty usage', () async {
      expect(await repository.read(kToday), DailyUsage.empty(kToday));
      expect(
        await repository.watchToday(kToday).first,
        DailyUsage.empty(kToday),
      );
    });

    test('recordCapture is visible through the stream', () async {
      await repository.recordCapture(kToday, taskCount: 4);

      expect(
        await repository.watchToday(kToday).first,
        DailyUsage(day: kToday, captureCount: 1, taskCount: 4),
      );
    });

    test('remaining counts down and floors at zero', () async {
      for (int i = 0; i < 7; i++) {
        await repository.recordCapture(kToday, taskCount: 1);
      }

      final DailyUsage usage = await repository.read(kToday);
      expect(usage.captureCount, 7);
      expect(usage.remaining(5), 0);
    });

    test('prune uses the repository default retention', () async {
      await repository.recordCapture(kToday.addDays(-120), taskCount: 1);
      await repository.recordCapture(kToday, taskCount: 1);

      await repository.prune(kToday);

      expect(
        await repository.read(kToday.addDays(-120)),
        DailyUsage.empty(kToday.addDays(-120)),
      );
      expect((await repository.read(kToday)).captureCount, 1);
    });

    test('"Delete all data" cannot reset the free quota', () async {
      // `databaseResetProvider` calls prune(today, keepDays: 0). Every earlier
      // day goes; today's count stays, or wiping the app's data would be a
      // way to get another free capture every day.
      await repository.recordCapture(kToday.addDays(-1), taskCount: 2);
      await repository.recordCapture(kToday, taskCount: 1);

      await repository.prune(kToday, keepDays: 0);

      expect(
        await repository.read(kToday.addDays(-1)),
        DailyUsage.empty(kToday.addDays(-1)),
      );
      expect((await repository.read(kToday)).captureCount, 1);
    });
  });
}
