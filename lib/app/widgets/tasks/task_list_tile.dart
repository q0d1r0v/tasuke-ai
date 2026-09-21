import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/tasks/check_circle.dart';
import 'package:tasuke_ai/app/widgets/tasks/date_chip.dart';
import 'package:tasuke_ai/app/widgets/tasuke_card.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

/// One saved task in a list.
///
/// The day and time arrive as **already formatted labels**. The tile cannot
/// work them out itself: "Today" is a question about the user's calendar, which
/// needs a `Clock`, and no widget in this catalogue is allowed one.
class TaskListTile extends StatelessWidget {
  const TaskListTile({
    required this.task,
    required this.onToggle,
    this.onTap,
    this.strikeWhenDone = true,
    this.showDate = true,
    this.relativeDayLabel,
    this.timeLabel,
    super.key,
  });

  final Task task;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final bool strikeWhenDone;
  final bool showDate;

  /// "Today", "Tomorrow", "Friday".
  final String? relativeDayLabel;

  /// "10:00 AM".
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final bool struck = strikeWhenDone && task.completed;
    final bool hasMeta =
        showDate && (relativeDayLabel != null || timeLabel != null);

    return TasukeCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: TasukeSpacing.md,
        vertical: TasukeSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          CheckCircle(checked: task.completed, onChanged: onToggle),
          const SizedBox(width: TasukeSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  task.title,
                  style: TasukeTypography.taskTitle.copyWith(
                    color: task.completed
                        ? TasukeColors.inkFaint
                        : TasukeColors.ink,
                    decoration: struck ? TextDecoration.lineThrough : null,
                    decorationColor: TasukeColors.inkFaint,
                  ),
                  // Three lines, then ellipsis. A 200-character title is
                  // allowed by the domain and would otherwise be a paragraph
                  // in the middle of a list.
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasMeta) ...<Widget>[
                  const SizedBox(height: TasukeSpacing.xs + 2),
                  DateChip(
                    dateLabel: relativeDayLabel,
                    timeLabel: timeLabel,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
