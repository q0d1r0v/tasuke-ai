import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// "Today · 10:00 AM" in a pill, with a calendar glyph.
///
/// It takes **labels**, never a date: formatting needs a locale and a
/// `Clock`, and neither belongs in a widget.
class DateChip extends StatelessWidget {
  const DateChip({
    this.dateLabel,
    this.timeLabel,
    this.onTap,
    this.compact = false,
    this.flagged = false,
    super.key,
  });

  final String? dateLabel;
  final String? timeLabel;
  final VoidCallback? onTap;

  /// The inline version inside a task row, as opposed to the tappable one on
  /// the Confirm card.
  final bool compact;

  /// A date the extractor was not sure about.
  ///
  /// Gold rather than red: it is "look at this", not "this is wrong", and the
  /// Confirm screen is already asking the user to check every row.
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    // `taskMetaRelative` rather than a separator of this widget's own: the
    // order of day and time, and whatever sits between them, is a translation
    // decision and the ARB already owns it.
    final String? date = dateLabel;
    final String? time = timeLabel;
    final String text = switch ((date, time)) {
      (final String d, final String t) => context.l10n.taskMetaRelative(d, t),
      (final String d, null) => d,
      (null, final String t) => t,
      (null, null) => context.l10n.taskNoDate,
    };

    final Color background = flagged
        ? TasukeColors.goldTint
        : TasukeColors.primaryTint;
    final Color glyph = flagged ? TasukeColors.gold : TasukeColors.primary;

    final Widget pill = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: TasukeRadii.rPill,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? TasukeSpacing.sm : TasukeSpacing.md,
          vertical: compact ? TasukeSpacing.xs : TasukeSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.calendar_today_rounded,
              size: TasukeSpacing.md + 2,
              color: glyph,
            ),
            const SizedBox(width: TasukeSpacing.xs + 2),
            // Flexible, not Expanded: this Row hugs its content, and an
            // Expanded child inside a MainAxisSize.min Row throws.
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TasukeTypography.label.copyWith(
                  color: TasukeColors.inkBody,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return pill;

    return Semantics(
      button: true,
      label: text,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: TasukeRadii.rPill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: TasukeRadii.rPill,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: TasukeMetrics.minTapTarget,
            ),
            child: Center(widthFactor: 1, child: ExcludeSemantics(child: pill)),
          ),
        ),
      ),
    );
  }
}
