import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

/// Edits a draft's date, time and reminder in one sheet.
///
/// Returns the edited draft, or null if the user dismissed it.
Future<TaskDraft?> showDraftDateSheet(
  BuildContext context, {
  required TaskDraft draft,
  required LocalDate today,
}) {
  return showModalBottomSheet<TaskDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TasukeColors.surface,
    builder: (BuildContext context) =>
        _DraftDateSheet(draft: draft, today: today),
  );
}

class _DraftDateSheet extends StatefulWidget {
  const _DraftDateSheet({required this.draft, required this.today});

  final TaskDraft draft;
  final LocalDate today;

  @override
  State<_DraftDateSheet> createState() => _DraftDateSheetState();
}

class _DraftDateSheetState extends State<_DraftDateSheet> {
  late TaskDraft _draft = widget.draft;

  Future<void> _pickDate() async {
    final DateTime initial = (_draft.date ?? widget.today).toDateTimeLocal();
    final DateTime first = widget.today.addDays(-365).toDateTimeLocal();
    final DateTime last = widget.today.addDays(3650).toDateTimeLocal();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      _draft = _draft.copyWith(
        date: LocalDate(picked.year, picked.month, picked.day),
      );
    });
  }

  Future<void> _pickTime() async {
    final LocalTimeOfDay current = _draft.time ?? const LocalTimeOfDay.hm(9, 0);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    setState(() {
      _draft = _draft.copyWith(
        // A time with no date is meaningless, so picking one implies today.
        date: _draft.date ?? widget.today,
        time: LocalTimeOfDay.hm(picked.hour, picked.minute),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(context.l10n.taskFieldDate, style: TasukeTypography.titleSm),
            const SizedBox(height: TasukeSpacing.lg),
            SettingsGroup(
              children: <Widget>[
                SettingsRow(
                  title: context.l10n.taskFieldDate,
                  leading: const IconTile(
                    icon: Icon(Icons.calendar_today_rounded),
                  ),
                  trailing: Text(
                    _draft.date == null
                        ? context.l10n.taskNoDate
                        : DateLabels.day(context, _draft.date!, widget.today),
                    style: TasukeTypography.label,
                  ),
                  onTap: _pickDate,
                ),
                SettingsRow(
                  title: context.l10n.taskFieldTime,
                  leading: const IconTile(icon: Icon(Icons.schedule_rounded)),
                  trailing: Text(
                    _draft.time == null
                        ? context.l10n.taskAllDay
                        : DateLabels.time(context, _draft.time!),
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
                    value: _draft.hasReminder,
                    semanticLabel: context.l10n.taskFieldReminder,
                    // A reminder with no date has nothing to fire against.
                    onChanged: _draft.date == null
                        ? null
                        : (bool value) => setState(() {
                            _draft = _draft.copyWith(hasReminder: value);
                          }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TasukeSpacing.lg),
            if (_draft.date != null)
              TextLinkButton(
                label: context.l10n.actionClear,
                onPressed: () => setState(() {
                  _draft = _draft.copyWith(clearDate: true, hasReminder: false);
                }),
              ),
            const SizedBox(height: TasukeSpacing.lg),
            PrimaryButton(
              label: context.l10n.actionDone,
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ],
        ),
      ),
    );
  }
}
