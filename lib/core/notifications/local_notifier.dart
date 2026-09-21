import 'package:tasuke_ai/core/time/local_date_time.dart';

/// A scheduled reminder, as the OS sees it.
final class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.atLocal,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;

  /// A **civil** date-time. The implementation resolves it against the current
  /// zone at scheduling time — it is never stored as an instant.
  final LocalDateTime atLocal;

  /// `{"taskId": "..."}`, JSON-encoded.
  final String payload;
}

/// How precisely the OS was able to schedule.
enum SchedulePrecision {
  exact,

  /// Android 12+ refused SCHEDULE_EXACT_ALARM, so the reminder may arrive up
  /// to ~15 minutes late. The UI says so once rather than failing.
  inexact,
}

/// The local-notification port.
///
/// The only implementation is the one importer of
/// `package:flutter_local_notifications` in the whole app — a guard test
/// enforces that, because every other file reaching a MethodChannel directly
/// is a file no widget test can exercise.
abstract interface class LocalNotifier {
  /// Initialises the plugin and the timezone database. Idempotent.
  Future<void> initialise();

  /// Whether notifications are permitted right now.
  Future<bool> hasPermission();

  Future<bool> requestPermission();

  /// Whether the OS will honour exact alarms. Always true on iOS.
  Future<bool> canScheduleExact();

  /// Opens Android's "Alarms & reminders" special-access screen. No-op on iOS.
  Future<bool> requestExactAlarmPermission();

  Future<ScheduleResult> schedule(ScheduledReminder reminder);

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// The ids the OS currently holds. Used by the orphan sweep.
  Future<List<int>> pendingIds();

  /// The payload of the notification that launched the app, if any.
  ///
  /// Consumed on read: an unread launch payload replayed on the next cold start
  /// opens a task the user already dealt with.
  Future<String?> consumeLaunchPayload();

  /// Taps that arrive while the app is running.
  Stream<String> get taps;
}

/// The outcome of a schedule call.
final class ScheduleResult {
  const ScheduleResult(this.precision);

  final SchedulePrecision precision;
}
