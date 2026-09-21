/// Keeps the OS's set of pending reminders in step with the database.
///
/// Every write path calls [sync] rather than scheduling directly, so there is
/// exactly one place that decides what the OS holds — which is what makes
/// "edit a task, the old alarm is cancelled first" a property of the system
/// rather than of each caller remembering to do it.
abstract interface class ReminderScheduler {
  /// Recomputes the rolling window and applies the diff.
  Future<SyncOutcome> sync();

  Future<void> cancelAll();
}

final class SyncOutcome {
  const SyncOutcome({
    required this.scheduled,
    required this.cancelled,
    required this.exact,
    this.skippedReason,
  });

  static const SyncOutcome noop = SyncOutcome(
    scheduled: 0,
    cancelled: 0,
    exact: true,
  );

  final int scheduled;
  final int cancelled;

  /// False when Android refused SCHEDULE_EXACT_ALARM and the reminders were
  /// scheduled inexactly. The UI says so once rather than failing.
  final bool exact;

  /// Set when the sync did nothing because it could not: no permission, or
  /// notifications switched off.
  final String? skippedReason;
}
