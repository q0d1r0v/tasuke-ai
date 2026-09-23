import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

/// Writes that change what the OS should be holding, paired with the sweep
/// that makes it hold it.
///
/// ⚠️ Why this is not inside `DriftTaskRepository`. That file states its own
/// rule — "Persists only. Nothing here talks to the notifier" — and the reason
/// is good: an alarm the OS refuses (no exact-alarm permission, doze, the
/// 64-notification cap) must never roll back a save the user has already seen
/// succeed. So the pairing belongs in a layer above the repository.
///
/// ⚠️ Why it exists at all. Ticking a task off in the task-detail screen
/// re-synced the reminders; ticking the same task off in the Home list — the
/// single most common interaction in the app — did not. Hours later the phone
/// buzzed about a task the user had already finished, and un-ticking one from
/// Completed never re-armed its alarm. One place, so the next list screen
/// cannot forget.
final class TaskActions {
  const TaskActions({required this._tasks, required this._reminders});

  final TaskRepository _tasks;
  final ReminderScheduler _reminders;

  /// ⚠️ The write is awaited BEFORE the sweep: `sync()` re-reads the rows to
  /// decide what the OS should hold, so a sweep that overlaps the write plans
  /// against the state it is replacing.
  Future<void> setCompleted(String id, {required bool completed}) async {
    await _tasks.setCompleted(id, completed: completed);
    await _reminders.sync();
  }
}

final Provider<TaskActions> taskActionsProvider = Provider<TaskActions>(
  (Ref ref) => TaskActions(
    tasks: ref.watch(taskRepositoryProvider),
    reminders: ref.watch(reminderSchedulerProvider),
  ),
);
