import 'dart:math' as math;

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
///
/// ⚠️ Two layouts, picked by measuring. The price sits beside the title only
/// while it fits there at its full size; a long store string ("UZS 499 000,00")
/// or large type stacks title, badge, price and period instead. The price
/// column used to share the row by flex, which capped it at 40% of the card
/// and shrank a UZS price to half size on a 320pt phone — and to a quarter at
/// 2× type, smaller than at 1× — while "Monthly" still broke as "Monthl / y".
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

  /// The widest the price column may be, as a share of the card's content
  /// width, and still sit beside the title.
  static const double sideBySidePriceShare = 0.45;

  /// Past this text scale the card stacks whatever the price: beside a price
  /// at 1.5× or 2×, the title column is too narrow for "Monthly" and a badge.
  static const double stackedTextScale = 1.3;

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
          child: Row(
            children: <Widget>[
              CheckCircle(checked: selected, onChanged: null),
              const SizedBox(width: TasukeSpacing.md),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return _isStacked(context, constraints.maxWidth)
                        ? _stacked()
                        : _sideBySide();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the card stacks at a content width of [width]: everything right
  /// of the check circle.
  bool _isStacked(BuildContext context, double width) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final double reference = TasukeTypography.titleSm.fontSize!;
    if (scaler.scale(reference) / reference > stackedTextScale) return true;
    final double priceColumn = math.max(
      _naturalWidth(context, price, TasukeTypography.price),
      _naturalWidth(context, period, TasukeTypography.bodySm),
    );
    return priceColumn > width * sideBySidePriceShare;
  }

  Widget _sideBySide() {
    return Row(
      children: <Widget>[
        Expanded(child: _heading()),
        const SizedBox(width: TasukeSpacing.md),
        // Its natural width, no flex: [_isStacked] has already checked that
        // it fits beside the title at full size.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _OneLine(
              price,
              style: TasukeTypography.price,
              alignment: AlignmentDirectional.centerEnd,
            ),
            _OneLine(
              period,
              style: TasukeTypography.bodySm,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ],
        ),
      ],
    );
  }

  Widget _stacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _titleAndBadge(),
        const SizedBox(height: TasukeSpacing.sm),
        // Scales down only past the whole content width, which at 2× type on
        // a 320pt phone still draws a UZS price larger than at 1×.
        _OneLine(price, style: TasukeTypography.price),
        _OneLine(period, style: TasukeTypography.bodySm),
        if (footnote != null) ...<Widget>[
          const SizedBox(height: TasukeSpacing.xs),
          Text(footnote!, style: TasukeTypography.caption),
        ],
      ],
    );
  }

  Widget _heading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _titleAndBadge(),
        if (footnote != null) ...<Widget>[
          const SizedBox(height: TasukeSpacing.xs),
          Text(footnote!, style: TasukeTypography.caption),
        ],
      ],
    );
  }

  /// The badge moves to its own line when the two do not fit on one; neither
  /// ever breaks inside a word.
  Widget _titleAndBadge() {
    return Wrap(
      spacing: TasukeSpacing.sm,
      runSpacing: TasukeSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _OneLine(title, style: TasukeTypography.titleSm),
        if (badge != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: _Badge(label: badge!),
          ),
      ],
    );
  }

  /// [text]'s width on one line, laid out exactly as its [Text] will be.
  static double _naturalWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    TextStyle effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }
}

/// One line that never breaks and is never clipped.
///
/// ⚠️ Scaled down rather than wrapped, and only when even the whole width is
/// too narrow for it. A break inside a word ("Monthl / y", "$3 / 9.9 / 9") is
/// what this card shipped with on a real device.
class _OneLine extends StatelessWidget {
  const _OneLine(
    this.text, {
    required this.style,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final String text;
  final TextStyle style;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(text, maxLines: 1, softWrap: false, style: style),
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
          maxLines: 1,
          softWrap: false,
          style: TasukeTypography.badge.copyWith(
            color: TasukeColors.primaryPressed,
          ),
        ),
      ),
    );
  }
}
