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

  @override
  Future<SyncOutcome> sync() {
    final Future<SyncOutcome> next = _queue.then((_) => _sync());
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

    final List<Task> candidates = await _tasks.allSchedulable(now);
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
    for (final PlannedReminder reminder in plan.toSchedule) {
      // Already held at the right moment? Re-scheduling it would be harmless on
      // iOS and a wasted AlarmManager slot on Android, so skip when the id is
      // held and the plan did not ask to cancel it.
      if (held.contains(reminder.notificationId) &&
          !plan.toCancel.contains(reminder.notificationId)) {
        continue;
      }
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
