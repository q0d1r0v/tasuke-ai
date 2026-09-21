import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/benefit_row.dart';

/// The task checkbox: a ring that fills, with a tick drawn on.
///
/// `onChanged: null` makes it a static glyph — that is how [BenefitRow] reuses
/// it — and a static glyph gets neither the 48pt tap box nor a semantics action.
class CheckCircle extends StatelessWidget {
  const CheckCircle({
    required this.checked,
    required this.onChanged,
    this.size = TasukeMetrics.checkCircle,
    this.checkedColor,
    super.key,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final double size;
  final Color? checkedColor;

  @override
  Widget build(BuildContext context) {
    final Widget ring = TweenAnimationBuilder<double>(
      // begin is left null on purpose: the first build then starts at its end
      // value, so a list of completed tasks does not tick itself on scroll-in.
      tween: Tween<double>(end: checked ? 1 : 0),
      duration: TasukeDurations.normal,
      curve: Curves.easeOut,
      builder: (BuildContext context, double progress, Widget? child) {
        return CustomPaint(
          size: Size.square(size),
          painter: _CheckPainter(
            progress: progress,
            fill: checkedColor ?? TasukeColors.primary,
          ),
        );
      },
    );

    if (onChanged == null) return ExcludeSemantics(child: ring);

    return Semantics(
      checked: checked,
      label: checked
          ? context.l10n.taskMarkIncomplete
          : context.l10n.taskMarkComplete,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Only on the way in. A haptic for un-ticking rewards the undo as
          // loudly as the achievement, and the list is full of both.
          if (!checked) unawaited(HapticFeedback.selectionClick());
          onChanged!(!checked);
        },
        // The glyph is 24pt; the target around it is 48.
        child: SizedBox.square(
          dimension: TasukeMetrics.minTapTarget,
          child: Center(child: ring),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress, required this.fill});

  /// 0 = empty ring, 1 = filled with a complete tick.
  final double progress;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = (size.shortestSide / 2) - 0.75;

    if (progress < 1) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = TasukeColors.outlineSoft.withValues(alpha: 1 - progress),
      );
    }

    if (progress > 0) {
      canvas.drawCircle(centre, radius * progress, Paint()..color = fill);
    }

    // The tick is drawn on only once the disc is most of the way in, so the
    // two do not read as one blurry shape at 120 Hz.
    final double tick = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    if (tick <= 0) return;

    final Path stroke = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.73, size.height * 0.35);

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = TasukeColors.onPrimary;

    if (tick >= 1) {
      canvas.drawPath(stroke, paint);
      return;
    }

    for (final PathMetric metric in stroke.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * tick), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.fill != fill;
}
