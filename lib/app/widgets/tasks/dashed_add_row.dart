import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// "Add another task" on the Confirm screen.
///
/// ⚠️ Flutter has no dashed border — `BorderSide` has no dash pattern and
/// `Border.all` cannot be given one — so the outline is a [CustomPainter] over
/// an `RRect` walked with `PathMetric`.
class DashedAddRow extends StatelessWidget {
  const DashedAddRow({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CustomPaint(
        painter: const _DashedBorderPainter(),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: TasukeRadii.rCard,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: TasukeRadii.rCard,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TasukeMetrics.controlHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TasukeSpacing.lg,
                  vertical: TasukeSpacing.md,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(
                        Icons.add_rounded,
                        size: TasukeSpacing.xl,
                        color: TasukeColors.primary,
                      ),
                      const SizedBox(width: TasukeSpacing.sm),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TasukeTypography.bodyLg.copyWith(
                            color: TasukeColors.primary,
                          ),
                        ),
                      ),
                    ],
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Offset.zero & size,
          topLeft: const Radius.circular(TasukeRadii.card),
          topRight: const Radius.circular(TasukeRadii.card),
          bottomLeft: const Radius.circular(TasukeRadii.card),
          bottomRight: const Radius.circular(TasukeRadii.card),
        ),
      );

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = TasukeColors.outlineSoft;

    for (final PathMetric metric in outline.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = (start + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
