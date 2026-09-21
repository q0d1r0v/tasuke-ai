import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/tables.dart';

part 'usage_dao.g.dart';

/// Reads and writes `usage_days`.
///
/// Every method takes a `'YYYY-MM-DD'` **local** day, computed by the caller
/// from a `Clock`. The DAO never derives a day itself: doing so would mean
/// either calling `DateTime.now()` here or asking sqlite for `'localtime'`, and
/// the second one answers with whatever zone the background isolate's C library
/// thinks it is in.
@DriftAccessor(tables: <Type>[UsageDays])
class UsageDao extends DatabaseAccessor<AppDatabase> with _$UsageDaoMixin {
  UsageDao(super.attachedDatabase);

  /// Null when the user has not captured anything today. The caller maps that
  /// to `DailyUsage.empty` rather than this DAO inventing a row — writing a
  /// zero row on read would make the quota banner a database write.
  Stream<UsageDayRow?> watchDay(String dayIso) => (select(
    usageDays,
  )..where(($UsageDaysTable t) => t.day.equals(dayIso))).watchSingleOrNull();

  Future<UsageDayRow?> readDay(String dayIso) => (select(
    usageDays,
  )..where(($UsageDaysTable t) => t.day.equals(dayIso))).getSingleOrNull();

  /// Adds one capture and [taskCount] tasks to [dayIso].
  ///
  /// ⚠️ An upsert with a read-free increment (`capture_count + 1` evaluated by
  /// SQLite), not select-then-write. The quota is the one number a user would
  /// notice being wrong in their favour *or* against it, and a read-modify-write
  /// from two isolates — the UI saving a capture while the notification isolate
  /// touches the same day — loses one of them.
  Future<void> recordCapture(String dayIso, {required int taskCount}) {
    return into(usageDays).insert(
      UsageDaysCompanion.insert(
        day: dayIso,
        captureCount: const Value<int>(1),
        taskCount: Value<int>(taskCount),
      ),
      onConflict: DoUpdate(
        (UsageDays old) => UsageDaysCompanion.custom(
          captureCount: old.captureCount + const Constant<int>(1),
          taskCount: old.taskCount + Constant<int>(taskCount),
        ),
      ),
    );
  }

  /// Drops every row strictly before [oldestDayIso].
  ///
  /// A lexicographic comparison on an ISO date, which is the whole reason the
  /// key is TEXT: no date maths, and the index serves the range directly.
  Future<void> pruneBefore(String oldestDayIso) => (delete(
    usageDays,
  )..where(($UsageDaysTable t) => t.day.isSmallerThanValue(oldestDayIso))).go();

  Future<void> deleteAll() => delete(usageDays).go();
}
