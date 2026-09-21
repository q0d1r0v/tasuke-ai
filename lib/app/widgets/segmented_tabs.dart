import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// The Today / Upcoming / Completed pill.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
    super.key,
  }) : assert(labels.length > 1, 'A single segment is not a control');

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TasukeColors.surface,
        borderRadius: TasukeRadii.rPill,
        border: Border.fromBorderSide(BorderSide(color: TasukeColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.xs),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double segment = constraints.maxWidth / labels.length;
            return Stack(
              children: <Widget>[
                // Positioned, so it paints first and therefore under the
                // labels. The Row below is the only non-positioned child, which
                // is what gives the Stack its height — there is no fixed one,
                // so the control grows with the type scale.
                AnimatedPositioned(
                  duration: TasukeDurations.fast,
                  curve: Curves.easeOut,
                  left: segment * selected,
                  width: segment,
                  top: 0,
                  bottom: 0,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: TasukeColors.primaryPressed,
                      borderRadius: TasukeRadii.rPill,
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < labels.length; i++)
                      Expanded(
                        child: _Segment(
                          label: labels[i],
                          selected: i == selected,
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: TasukeRadii.rPill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: TasukeRadii.rPill,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: TasukeMetrics.minTapTarget - TasukeSpacing.sm,
            ),
            child: Center(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TasukeSpacing.xs,
                  ),
                  child: Text(
                    label,
                    // Ellipsis rather than wrap: three segments of wrapped text
                    // at 2× scale turn a 40pt control into a 120pt one, and the
                    // labels are one word each.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TasukeTypography.tabLabel.copyWith(
                      color: selected
                          ? TasukeColors.onPrimary
                          : TasukeColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
