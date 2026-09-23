import 'dart:convert';

import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_plan.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

/// The payload key a tapped reminder carries.
const String kNotificationTaskIdKey = 'taskId';

String encodeReminderPayload(String taskId) =>
    jsonEncode(<String, String>{kNotificationTaskIdKey: taskId});

/// Reads `{"taskId": "..."}`. Returns null for anything else rather than
/// throwing — a malformed payload must open Home, not crash the launch.
String? decodeReminderPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      final Object? id = decoded[kNotificationTaskIdKey];
      if (id is String && id.isNotEmpty) return id;
    }
  } on FormatException {
    return null;
  }
  return null;
}

final class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler({
    required this._notifier,
    required this._tasks,
    required this._clock,
    required this._readSettings,
    required this._bodyBuilder,
  });

  final LocalNotifier _notifier;
  final TaskRepository _tasks;
  final Clock _clock;
  final Future<AppSettings> Function() _readSettings;
  final String Function(String title) _bodyBuilder;

  /// Serialises syncs.
  ///
  /// Two overlapping sweeps would each read the OS's held ids before the
  /// other's cancellations landed, and the loser would re-create alarms the
  /// winner had just removed.
  ///
  /// ⚠️ A chained future, not a `while (_inFlight != null) await _inFlight;`
  /// spin. Awaiting an already-completed future only yields a **microtask**,
  /// and Dart drains the entire microtask queue before it looks at timers or
  /// events — so a second caller that re-checks the flag after each await
  /// starves the event loop completely and the isolate stops responding. It
  /// looks exactly like a native hang, and neither a test timeout nor a
  /// watchdog can interrupt it.
  Future<void> _queue = Future<void>.value();

  /// The queued sweep that has not started yet. Every caller that arrives
  /// before it starts shares it.
  ///
  /// A tick, a title debounce and a resume each ask for a sweep, and each one
  /// used to get its own full re-arm of the window. Sharing is safe because
  /// every caller has committed its write before it calls [sync], and a sweep
  /// that has not started reads the database when it does.
  ///
  /// ⚠️ Cleared when the sweep STARTS, not when it finishes. A caller that
  /// arrives mid-sweep may have written after that sweep read the tasks, so it
  /// must get a sweep of its own.
  Future<SyncOutcome>? _pending;

  @override
  Future<SyncOutcome> sync() {
    final Future<SyncOutcome>? pending = _pending;
    if (pending != null) return pending;

    late final Future<SyncOutcome> next;
    next = _queue.then((_) {
      if (identical(_pending, next)) _pending = null;
      return _sync();
    });
    _pending = next;
    // Swallow the error on the chain itself: one failed sweep must not poison
    // every later one. Callers still see the error through [next].
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<SyncOutcome> _sync() async {
    final AppSettings settings = await _readSettings();
    final bool permitted = await _notifier.hasPermission();

    final LocalDateTime now = LocalDateTime.fromLocal(_clock.nowLocal());
    final Set<int> held = (await _notifier.pendingIds()).toSet();

    if (!permitted) {
      // No permission means the OS is holding nothing useful; clear whatever is
      // left so a later grant starts from a clean slate.
      for (final int id in held) {
        await _notifier.cancel(id);
      }
      return SyncOutcome(
        scheduled: 0,
        cancelled: held.length,
        exact: true,
        skippedReason: 'notifications-not-permitted',
      );
    }

    // From an hour back, not from now: an inexact alarm may still be on its
    // way after its minute has passed, and the planner has to see its task to
    // know not to cancel it. See [ReminderPlanner.inFlightMinutes].
    final List<Task> candidates = await _tasks.allSchedulable(
      now.subtractMinutes(ReminderPlanner.inFlightMinutes),
    );
    final ReminderPlan plan = ReminderPlanner.plan(
      tasks: candidates,
      now: now,
      heldIds: held,
      notificationsEnabled: settings.notificationsEnabled,
    );

    for (final int id in plan.toCancel) {
      await _notifier.cancel(id);
    }

    bool exact = true;
    int scheduled = 0;
    // ⚠️ Every reminder in the window is re-armed on every sweep, including
    // the ones the OS already "holds". `held` is the plugin's own cache of what
    // it once scheduled — ids only, no time — not what AlarmManager actually
    // holds. Skipping held ids, as this once did, meant:
    //   * a reminder moved from 17:00 to 18:00 kept ringing at 17:00,
    //   * a timezone change or a later exact-alarm grant changed nothing,
    //   * alarms the OS dropped (Force stop, an exact-alarm revocation, a
    //     reboot on a ROM that blocks the boot receiver, as HyperOS does)
    //     were never re-armed, because the cache still listed them.
    // Re-arming reuses the id, so it replaces the alarm rather than adding a
    // second one; it costs no extra AlarmManager slot. The notifier may skip a
    // re-arm, but only one this same process set with the identical instant,
    // precision and content — its memo lives in memory, and every way the OS
    // drops alarms wholesale also ends the process.
    for (final PlannedReminder reminder in plan.toSchedule) {
      try {
        final ScheduleResult result = await _notifier.schedule(
          ScheduledReminder(
            id: reminder.notificationId,
            title: reminder.title,
            body: _bodyBuilder(reminder.title),
            atLocal: reminder.atLocal,
            payload: encodeReminderPayload(reminder.taskId),
          ),
        );
        if (result.precision == SchedulePrecision.inexact) exact = false;
        scheduled++;
      } on Object catch (error, stack) {
        // One failed alarm must not abort the sweep: the task is already saved
        // and the user's other reminders still matter.
        Log.e(
          'reminder schedule failed for ${reminder.notificationId}',
          error,
          stack,
        );
      }
    }

    return SyncOutcome(
      scheduled: scheduled,
      cancelled: plan.toCancel.length,
      exact: exact,
    );
  }

  @override
  Future<void> cancelAll() => _notifier.cancelAll();
}
