import 'package:tasuke_ai/core/time/local_date.dart';

/// One local day's voice usage.
final class DailyUsage {
  const DailyUsage({
    required this.day,
    required this.captureCount,
    required this.taskCount,
  });

  factory DailyUsage.empty(LocalDate day) =>
      DailyUsage(day: day, captureCount: 0, taskCount: 0);

  final LocalDate day;

  /// Only **successful** captures count. A capture that hit silence or failed
  /// to transcribe must not consume quota — that is the complaint users file.
  final int captureCount;

  final int taskCount;

  int remaining(int limit) {
    final int left = limit - captureCount;
    return left < 0 ? 0 : left;
  }

  @override
  bool operator ==(Object other) =>
      other is DailyUsage &&
      other.day == day &&
      other.captureCount == captureCount &&
      other.taskCount == taskCount;

  @override
  int get hashCode => Object.hash(day, captureCount, taskCount);
}

abstract interface class UsageRepository {
  Stream<DailyUsage> watchToday(LocalDate today);

  Future<DailyUsage> read(LocalDate day);

  /// Records one successful capture. Called **after** tasks are saved, never
  /// before the recorder starts.
  Future<void> recordCapture(LocalDate day, {required int taskCount});

  /// Drops rows older than [keepDays].
  Future<void> prune(LocalDate today, {int keepDays});
}
