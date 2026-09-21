import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/usage_dao.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

final class DriftUsageRepository implements UsageRepository {
  DriftUsageRepository({required this.dao});

  final UsageDao dao;

  /// ⚠️ [today] is passed in, not derived. The quota's whole contract is that
  /// it resets at the user's own midnight, and the only way to be sure of that
  /// is for the caller — which watches `todayProvider` and re-reads on resume —
  /// to say which day it means.
  @override
  Stream<DailyUsage> watchToday(LocalDate today) => dao
      .watchDay(today.toIso())
      .map((UsageDayRow? row) => _toUsage(row, today));

  @override
  Future<DailyUsage> read(LocalDate day) async =>
      _toUsage(await dao.readDay(day.toIso()), day);

  /// ⚠️ Called **after** the tasks are saved, never when the recorder starts.
  ///
  /// A capture that hit silence, failed to transcribe, or was cancelled has not
  /// cost the user anything and must not cost them a quota slot either. Moving
  /// this call earlier is the single easiest way to earn a one-star review.
  @override
  Future<void> recordCapture(LocalDate day, {required int taskCount}) =>
      dao.recordCapture(day.toIso(), taskCount: taskCount);

  @override
  Future<void> prune(LocalDate today, {int keepDays = kUsageRetentionDays}) =>
      dao.pruneBefore(today.addDays(-keepDays).toIso());

  /// A missing row is zero usage, not an error and not a row to create: reading
  /// the quota banner must never write to the database.
  static DailyUsage _toUsage(UsageDayRow? row, LocalDate day) => row == null
      ? DailyUsage.empty(day)
      : DailyUsage(
          day: day,
          captureCount: row.captureCount,
          taskCount: row.taskCount,
        );
}
