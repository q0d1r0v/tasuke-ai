import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/tasks/date_chip.dart';
import 'package:tasuke_ai/app/widgets/tasuke_card.dart';
import 'package:tasuke_ai/app/widgets/tasuke_text_field.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

/// One row of the Confirm screen: an editable title, a date chip and a delete.
///
/// The card owns a [TextEditingController] but not the draft — every keystroke
/// goes straight out through [onChanged], so the screen's list stays the single
/// source of truth and "Save" cannot write a stale title.
class EditableTaskCard extends StatefulWidget {
  const EditableTaskCard({
    required this.draft,
    required this.onChanged,
    required this.onDelete,
    required this.onEditDate,
    required this.dateLabelBuilder,
    super.key,
  });

  final TaskDraft draft;
  final ValueChanged<TaskDraft> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onEditDate;

  /// Renders the draft's date the way the screen wants it — "Tomorrow, 3:00 PM"
  /// or "No date". A builder rather than a string so the card re-reads it after
  /// the date picker returns.
  final String Function(TaskDraft) dateLabelBuilder;

  @override
  State<EditableTaskCard> createState() => _EditableTaskCardState();
}

class _EditableTaskCardState extends State<EditableTaskCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.title,
  );

  @override
  void didUpdateWidget(EditableTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ Guarded, and not just assigned. Setting `.text` replaces the whole
    // editing value and collapses the selection to the end of it — so a parent
    // that echoes each keystroke straight back would throw the caret to the end
    // of the line every time the user edits the middle of a title.
    if (widget.draft.title != _controller.text) {
      _controller.text = widget.draft.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool flagged = widget.draft.lowConfidenceDate;

    return TasukeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TasukeTextField(
                  controller: _controller,
                  hint: context.l10n.taskFieldTitleHint,
                  // Two lines: spoken tasks run long, and a single-line field
                  // hides the end of what the user just said.
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  onChanged: (String value) =>
                      widget.onChanged(widget.draft.copyWith(title: value)),
                ),
              ),
              const SizedBox(width: TasukeSpacing.sm),
              IconButton(
                onPressed: widget.onDelete,
                tooltip: context.l10n.actionDelete,
                color: TasukeColors.inkFaint,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.md),
          Row(
            children: <Widget>[
              Flexible(
                child: DateChip(
                  dateLabel: widget.dateLabelBuilder(widget.draft),
                  onTap: widget.onEditDate,
                  flagged: flagged,
                ),
              ),
              if (flagged) ...<Widget>[
                const SizedBox(width: TasukeSpacing.sm),
                Flexible(
                  child: Text(
                    context.l10n.confirmLowConfidence,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TasukeTypography.caption.copyWith(
                      color: TasukeColors.gold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
