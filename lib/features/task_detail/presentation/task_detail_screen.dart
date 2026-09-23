import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override`, `ProviderListenable` or the
// `*Family` types from its main library — only from `misc.dart`. Naming any of
// them without this import is a `non_type_as_type_argument` error that reads
// like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/notification_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/tasks/data/task_mapper.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

final StreamProviderFamily<Task?, String> taskByIdProvider =
    StreamProvider.family<Task?, String>((Ref ref, String id) {
      return ref.watch(taskRepositoryProvider).watchById(id);
    });

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  /// The last task the stream delivered, for the frames after a delete.
  Task? _last;

  @override
  Widget build(BuildContext context) {
    return TasukeScaffold(
      title: context.l10n.taskDetailTitle,
      showBack: true,
      scrollable: false,
      child: AsyncValueView<Task?>(
        value: ref.watch(taskByIdProvider(widget.taskId)),
        data: (Task? task) {
          if (task != null) {
            _last = task;
            return _Body(task: task);
          }
          // ⚠️ Deleted from this screen: the stream's null lands while the
          // route is still sliding out, and the empty state below flashed
          // "Please try again." on every delete. A leaving route ignores
          // pointers, so the old page is safe to keep on screen.
          final Task? last = _last;
          final bool leaving = !(ModalRoute.of(context)?.isCurrent ?? true);
          if (leaving && last != null) return _Body(task: last);
          // Reachable from a notification whose task was deleted while the
          // process was dead. Not an error — just gone.
          return EmptyState(
            title: context.l10n.taskDeleted,
            message: context.l10n.errorGenericBody,
            actionLabel: context.l10n.actionGotIt,
            onAction: () => context.go('/home'),
            icon: Icons.task_alt_rounded,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.task});

  final Task task;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final TextEditingController _title = TextEditingController(
    text: widget.task.title,
  );
  Timer? _debounce;

  // ⚠️ Held, not re-read. The title is also saved from dispose() and after
  // awaits, where `ref` throws once the page is unmounted. All three are
  // keep-alive providers that outlive this page.
  late final TaskRepository _tasks;
  late final SettingsRepository _settings;
  late final ReminderScheduler _scheduler;

  @override
  void initState() {
    super.initState();
    _tasks = ref.read(taskRepositoryProvider);
    _settings = ref.read(settingsRepositoryProvider);
    _scheduler = ref.read(reminderSchedulerProvider);
  }

  @override
  void dispose() {
    // ⚠️ Leaving is how a title edit is finished, and a cancelled debounce
    // used to drop whatever was typed in its last 400 ms.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(
        _saveTitle(_title.text).catchError((Object error, StackTrace stack) {
          Log.e('saving the title on exit failed', error, stack);
        }),
      );
    }
    _title.dispose();
    super.dispose();
  }

  /// Writes [next], keeping the reminder in step with the due time.
  ///
  /// ⚠️ `reminder.at` is DERIVED from `due`, and it is recomputed here on
  /// every date, time and reminder edit rather than by each call site. The
  /// date and time pickers used to write `due` alone, so editing a task's time
  /// left its alarm at the old one: a user who moved a call to 6:11 PM had a
  /// reminder still pointed at 5:29 PM — already past, so the scheduler
  /// skipped it, and nothing rang at either time. The scheduler fires on
  /// `reminder.at`, never on `due`.
  ///
  /// ⚠️ A title-only edit leaves `reminder.at` as stored. An all-day reminder
  /// for today moves to the first quarter hour at least five minutes ahead
  /// once its minute has passed (see [TaskMapper.resolveReminderAt]);
  /// re-deriving it on a later title edit
  /// would move it again and re-arm an alarm that has already rung.
  ///
  /// [askForNotifications] is set by the edits that make a reminder matter —
  /// the switch, the date, the time — and deliberately NOT by a title edit, so
  /// the OS permission dialog can never pop up while the user is typing.
  Future<void> _persist(Task next, {bool askForNotifications = false}) async {
    final TaskDue? due = next.due;
    Task synced = next;
    if (due != null && (askForNotifications || due != widget.task.due)) {
      final LocalDateTime now = LocalDateTime.fromLocal(
        ref.read(clockProvider).nowLocal(),
      );
      final int allDayMinute = (await _settings.read()).allDayReminderMinute;
      synced = next.copyWith(
        reminder: next.reminder.copyWith(
          at: TaskMapper.resolveReminderAt(
            due,
            allDayReminderMinute: allDayMinute,
            now: now,
          ),
        ),
      );
    }

    await _tasks.update(synced);

    if (askForNotifications && synced.reminder.enabled && mounted) {
      try {
        await ensureReminderPermissions(
          ref.read(permissionServiceProvider),
          alreadyPrompted: () => ref.read(exactAlarmPromptedProvider),
          markPrompted: ref.read(exactAlarmPromptedProvider.notifier).complete,
        );
      } on Object catch (error, stack) {
        Log.e('asking for the notification permission failed', error, stack);
      }
    }

    // Any change to a date, a time or the reminder switch changes what the OS
    // should be holding, so the sweep runs on every write rather than each call
    // site remembering to.
    unawaited(_scheduler.sync());
  }

  Future<void> _saveTitle(String value) async {
    final String normalised = TaskTitle.normalise(value);
    if (normalised.isEmpty || normalised == widget.task.title) return;
    await _persist(widget.task.copyWith(title: normalised));
  }

  void _onTitleChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_saveTitle(value)),
    );
  }

  Future<void> _pickDate() async {
    final LocalDate today = ref.read(todayProvider);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (widget.task.due?.date ?? today).toDateTimeLocal(),
      firstDate: today.addDays(-365).toDateTimeLocal(),
      lastDate: today.addDays(3650).toDateTimeLocal(),
    );
    if (picked == null) return;
    final LocalDate date = LocalDate(picked.year, picked.month, picked.day);
    await _persist(
      widget.task.copyWith(
        due: TaskDue(date: date, time: widget.task.due?.time),
        updatedAt: ref.read(clockProvider).nowUtc(),
      ),
      askForNotifications: true,
    );
  }

  Future<void> _pickTime() async {
    final LocalDate today = ref.read(todayProvider);
    final LocalTimeOfDay current =
        widget.task.due?.time ?? const LocalTimeOfDay.hm(9, 0);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    await _persist(
      widget.task.copyWith(
        due: TaskDue(
          date: widget.task.due?.date ?? today,
          time: LocalTimeOfDay.hm(picked.hour, picked.minute),
        ),
        updatedAt: ref.read(clockProvider).nowUtc(),
      ),
      askForNotifications: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Task task = widget.task;
    final LocalDate today = ref.watch(todayProvider);
    final bool overdue = task.isOverdue(today);

    return ListView(
      padding: const EdgeInsets.only(bottom: TasukeSpacing.xxl),
      children: <Widget>[
        TasukeTextField(
          controller: _title,
          hint: context.l10n.taskFieldTitleHint,
          maxLines: 3,
          onChanged: _onTitleChanged,
        ),
        if (overdue) ...<Widget>[
          const SizedBox(height: TasukeSpacing.md),
          Text(
            context.l10n.taskOverdue,
            style: TasukeTypography.label.copyWith(color: TasukeColors.danger),
          ),
        ],
        const SizedBox(height: TasukeSpacing.xl),
        SettingsGroup(
          children: <Widget>[
            SettingsRow(
              title: context.l10n.taskFieldDate,
              leading: const IconTile(icon: Icon(Icons.calendar_today_rounded)),
              trailing: Text(
                task.due == null
                    ? context.l10n.taskNoDate
                    : DateLabels.day(context, task.due!.date, today),
                style: TasukeTypography.label,
              ),
              onTap: _pickDate,
            ),
            SettingsRow(
              title: context.l10n.taskFieldTime,
              leading: const IconTile(icon: Icon(Icons.schedule_rounded)),
              trailing: Text(
                task.due?.time == null
                    ? context.l10n.taskAllDay
                    : DateLabels.time(context, task.due!.time!),
                style: TasukeTypography.label,
              ),
              onTap: _pickTime,
            ),
            SettingsRow(
              title: context.l10n.taskFieldReminder,
              leading: const IconTile(
                icon: Icon(Icons.notifications_active_outlined),
              ),
              showChevron: false,
              isLast: true,
              trailing: TasukeSwitch(
                value: task.reminder.enabled,
                semanticLabel: context.l10n.taskFieldReminder,
                onChanged: task.due == null
                    ? null
                    : (bool value) => _persist(
                        task.copyWith(
                          reminder: task.reminder.copyWith(enabled: value),
                          updatedAt: ref.read(clockProvider).nowUtc(),
                        ),
                        askForNotifications: true,
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: TasukeSpacing.xl),
        TasukeCard(
          onTap: () async {
            final bool nowCompleted = !task.completed;
            await ref
                .read(taskRepositoryProvider)
                .setCompleted(task.id, completed: nowCompleted);
            unawaited(ref.read(reminderSchedulerProvider).sync());
            // Reopening says nothing: the label flipping back is the feedback,
            // and "Task completed" there said the opposite of what happened.
            if (!context.mounted || !nowCompleted) return;
            AppSnack.success(context, context.l10n.taskCompleted);
          },
          child: Row(
            children: <Widget>[
              Icon(
                task.completed
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: task.completed
                    ? TasukeColors.success
                    : TasukeColors.outlineSoft,
              ),
              const SizedBox(width: TasukeSpacing.md),
              Text(
                task.completed
                    ? context.l10n.taskMarkIncomplete
                    : context.l10n.taskMarkComplete,
                style: TasukeTypography.bodyLg,
              ),
            ],
          ),
        ),
        const SizedBox(height: TasukeSpacing.xxl),
        DangerButton(
          label: context.l10n.taskDelete,
          leading: Icons.delete_outline_rounded,
          onPressed: () async {
            final bool confirmed = await showDeleteTaskDialog(context) ?? false;
            if (!confirmed) return;
            await ref.read(taskRepositoryProvider).delete(task.id);
            unawaited(ref.read(reminderSchedulerProvider).sync());
            if (!context.mounted) return;
            context.pop();
            AppSnack.info(context, context.l10n.taskDeleted);
          },
        ),
      ],
    );
  }
}
