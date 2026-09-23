import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

/// One reminder the OS should be holding.
final class PlannedReminder {
  const PlannedReminder({
    required this.notificationId,
    required this.taskId,
    required this.title,
    required this.atLocal,
  });

  final int notificationId;
  final String taskId;
  final String title;
  final LocalDateTime atLocal;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.notificationId == notificationId &&
      other.taskId == taskId &&
      other.atLocal == atLocal;

  @override
  int get hashCode => Object.hash(notificationId, taskId, atLocal);
}

/// What the OS should be holding, and what it should not.
final class ReminderPlan {
  const ReminderPlan({required this.toSchedule, required this.toCancel});

  final List<PlannedReminder> toSchedule;
  final List<int> toCancel;

  bool get isEmpty => toSchedule.isEmpty && toCancel.isEmpty;
}

/// Decides which reminders belong in the OS right now.
///
/// Pure: it takes the tasks, the current civil time and the ids the OS already
/// holds, and returns a diff. Every scheduling rule the app has is therefore a
/// one-line test rather than a mock of a platform channel.
abstract final class ReminderPlanner {
  /// How many reminders are kept live at once.
  ///
  /// ⚠️ Two hard platform limits force a rolling window rather than "schedule
  /// everything":
  ///   * iOS delivers only the **64** soonest pending local notifications and
  ///     silently drops the rest.
  ///   * Samsung caps `AlarmManager` at **500** alarms per app and throws past it.
  ///
  /// 60 leaves headroom under the iOS limit for anything scheduled outside this
  /// planner. The window is topped up on every app resume, on every write, at
  /// boot and on a timezone change.
  static const int windowSize = 60;

  /// How long after its minute a reminder may still be in the OS's hands.
  ///
  /// Without exact-alarm access Android delivers an inexact alarm up to an
  /// hour late. A sweep in that gap — the user opening the app at 18:12 for an
  /// 18:11 reminder the OS has deferred to 18:40 — must not treat the pending
  /// alarm as an orphan and cancel it, or the reminder never arrives at all.
  static const int inFlightMinutes = 60;

  /// Builds the diff.
  ///
  /// [tasks] must already be filtered to incomplete tasks with a reminder
  /// enabled; [heldIds] is what the OS currently has.
  static ReminderPlan plan({
    required List<Task> tasks,
    required LocalDateTime now,
    required Set<int> heldIds,
    required bool notificationsEnabled,
  }) {
    // The Settings switch is a kill switch, not a filter: turning it off means
    // the OS holds nothing at all, so a user who revokes consent stops being
    // interrupted immediately rather than at the next sync.
    if (!notificationsEnabled) {
      return ReminderPlan(
        toSchedule: const <PlannedReminder>[],
        toCancel: heldIds.toList(),
      );
    }

    final List<PlannedReminder> wanted = <PlannedReminder>[];
    final Set<int> inFlight = <int>{};
    final LocalDateTime inFlightFrom = now.subtractMinutes(inFlightMinutes);
    for (final Task task in tasks) {
      final LocalDateTime? at = task.reminder.at;
      final int? id = task.reminder.notificationId;
      if (at == null || id == null) continue;
      if (task.completed || !task.reminder.enabled) continue;
      // A reminder whose moment has passed is not rescheduled. It is not an
      // error either: "3 PM" said at 4 PM already rolled to tomorrow in the
      // parser, so anything still in the past here is a task the user knowingly
      // backdated. But if its minute passed only recently the OS may still be
      // about to deliver it, so it is left alone rather than cancelled.
      if (!at.isAfter(now)) {
        if (at.isAfter(inFlightFrom)) inFlight.add(id);
        continue;
      }
      wanted.add(
        PlannedReminder(
          notificationId: id,
          taskId: task.id,
          title: task.title,
          atLocal: at,
        ),
      );
    }

    wanted.sort(
      (PlannedReminder a, PlannedReminder b) => a.atLocal.compareTo(b.atLocal),
    );
    final List<PlannedReminder> window = wanted.length > windowSize
        ? wanted.sublist(0, windowSize)
        : wanted;

    final Set<int> wantedIds = window
        .map((PlannedReminder r) => r.notificationId)
        .toSet();

    // Everything the OS holds that is not in the window is cancelled. That
    // sweep is what clears orphans left by a task deleted while the process was
    // dead, and what drops reminders pushed out of the window by newer ones.
    final List<int> toCancel =
        heldIds
            .where(
              (int id) => !wantedIds.contains(id) && !inFlight.contains(id),
            )
            .toList()
          ..sort();

    return ReminderPlan(toSchedule: window, toCancel: toCancel);
  }

  /// A stable notification id for a task.
  ///
  /// Derived from the task id so that editing a task targets the same OS alarm
  /// slot instead of leaking a new one every save. Folded into the positive
  /// 31-bit range because Android's `AlarmManager` request codes are signed
  /// 32-bit ints and a negative id is silently dropped on some OEM builds.
  static int notificationIdFor(String taskId) {
    int hash = 0x811c9dc5;
    for (final int unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // ⚠️ Masked on the way OUT as well as inside the loop. An empty task id
    // never enters the loop at all, and the bare FNV seed (0x811c9dc5) is
    // larger than 2^31 — which Android reads back as a *negative* request
    // code, the one value this function exists to avoid.
    hash &= 0x7fffffff;
    // 0 is a legal id but is used by several plugins as a sentinel; shift off it.
    return hash == 0 ? 1 : hash;
  }
}
