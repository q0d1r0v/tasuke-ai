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
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

final StreamProviderFamily<Task?, String> taskByIdProvider =
    StreamProvider.family<Task?, String>((Ref ref, String id) {
      return ref.watch(taskRepositoryProvider).watchById(id);
    });

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TasukeScaffold(
      title: context.l10n.taskDetailTitle,
      showBack: true,
      scrollable: false,
      child: AsyncValueView<Task?>(
        value: ref.watch(taskByIdProvider(taskId)),
        data: (Task? task) {
          if (task == null) {
            // Reachable from a notification whose task was deleted while the
            // process was dead. Not an error — just gone.
            return EmptyState(
              title: context.l10n.taskDeleted,
              message: context.l10n.errorGenericBody,
              actionLabel: context.l10n.actionGotIt,
              onAction: () => context.go('/home'),
              icon: Icons.task_alt_rounded,
            );
          }
          return _Body(task: task);
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

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    super.dispose();
  }

  Future<void> _persist(Task next) async {
    await ref.read(taskRepositoryProvider).update(next);
    // Any change to a date, a time or the reminder switch changes what the OS
    // should be holding, so the sweep runs on every write rather than each call
    // site remembering to.
    unawaited(ref.read(reminderSchedulerProvider).sync());
  }

  void _onTitleChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final String normalised = TaskTitle.normalise(value);
      if (normalised.isEmpty || normalised == widget.task.title) return;
      unawaited(_persist(widget.task.copyWith(title: normalised)));
    });
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
                    : (bool value) async {
                        final int allDayMinute =
                            (await ref.read(settingsRepositoryProvider).read())
                                .allDayReminderMinute;
                        await _persist(
                          task.copyWith(
                            reminder: task.reminder.copyWith(
                              enabled: value,
                              at: task.due!.resolve(allDayMinute: allDayMinute),
                            ),
                            updatedAt: ref.read(clockProvider).nowUtc(),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: TasukeSpacing.xl),
        TasukeCard(
          onTap: () async {
            await ref
                .read(taskRepositoryProvider)
                .setCompleted(task.id, completed: !task.completed);
            unawaited(ref.read(reminderSchedulerProvider).sync());
            if (!context.mounted) return;
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
