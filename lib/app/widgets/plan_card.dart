import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/tasks/check_circle.dart';
import 'package:tasuke_ai/app/widgets/tasuke_card.dart';

/// One subscription option on the paywall.
///
/// ⚠️ A card, not a [Radio] or a `RadioListTile`. `groupValue` and `onChanged`
/// on Radio are deprecated from Flutter 3.32 in favour of a `RadioGroup`
/// ancestor, the design draws a card rather than a dot, and the whole card —
/// price included — has to be the tap target.
class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.title,
    required this.price,
    required this.period,
    required this.selected,
    required this.onTap,
    this.badge,
    this.footnote,
    super.key,
  });

  final String title;
  final String price;
  final String period;
  final bool selected;
  final VoidCallback onTap;

  /// "Save 33%".
  final String? badge;

  /// "$3.33 per month, billed yearly".
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: TasukeCard(
          onTap: onTap,
          background: selected
              ? TasukeColors.primaryTint
              : TasukeColors.surface,
          border: Border.fromBorderSide(
            BorderSide(
              color: selected ? TasukeColors.primary : TasukeColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CheckCircle(checked: selected, onChanged: null),
                  const SizedBox(width: TasukeSpacing.md),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title, style: TasukeTypography.titleSm),
                        if (badge != null) ...<Widget>[
                          const SizedBox(height: TasukeSpacing.xs),
                          _Badge(label: badge!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: TasukeSpacing.sm),
                  // Flexible with wrapping text on both sides: at 2× the price
                  // and the title cannot both fit on one line, and the card is
                  // intrinsic height so it simply grows.
                  Flexible(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          price,
                          textAlign: TextAlign.end,
                          style: TasukeTypography.price,
                        ),
                        Text(
                          period,
                          textAlign: TextAlign.end,
                          style: TasukeTypography.bodySm,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (footnote != null) ...<Widget>[
                const SizedBox(height: TasukeSpacing.sm),
                Text(footnote!, style: TasukeTypography.caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TasukeColors.primaryWash,
        borderRadius: TasukeRadii.rPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TasukeSpacing.sm,
          vertical: TasukeSpacing.xs / 2,
        ),
        child: Text(
          label,
          style: TasukeTypography.badge.copyWith(
            color: TasukeColors.primaryPressed,
          ),
        ),
      ),
    );
  }
}
