import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// The app mark: a rounded gradient tile with a white waveform inside it.
///
/// Painted rather than loaded, so the splash and the About screen cannot
/// disagree with the launcher icon, and so it costs no asset decode on the one
/// frame where startup time is visible.
class TasukeLogo extends StatelessWidget {
  const TasukeLogo({this.size = 88, this.showWordmark = false, super.key});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final Widget mark = Semantics(
      image: true,
      label: context.l10n.appTitle,
      child: CustomPaint(
        size: Size.square(size),
        painter: const _LogoPainter(),
      ),
    );

    if (!showWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: mark),
        const SizedBox(height: TasukeSpacing.lg),
        Text(context.l10n.appTitle, style: TasukeTypography.wordmark),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  /// The glyph: one continuous stroke that dips and rises, like a voice trace.
  ///
  /// ⚠️ This must stay in step with `tool/`-generated launcher icon and the
  /// splash image, which draw the same curve from the same parameters. Two
  /// marks that are nearly the same are worse than one that is obviously
  /// different — the user sees the launcher icon and the in-app logo side by
  /// side on the splash, and a mismatch reads as the wrong app.
  static const int _samples = 96;

  /// Fractions of the tile, never pixels, so the mark is identical at 32pt and
  /// at 160.
  static const double _spanFraction = 0.46;
  static const double _amplitudeFraction = 0.21;
  static const double _strokeFraction = 0.088;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect tile = Offset.zero & size;

    canvas.drawRRect(
      RRect.fromRectAndRadius(tile, Radius.circular(size.width * 0.225)),
      Paint()..shader = TasukeGradients.brand.createShader(tile),
    );

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double span = size.width * _spanFraction;
    final double amplitude = size.height * _amplitudeFraction;

    final Path path = Path();
    for (int i = 0; i <= _samples; i++) {
      final double t = i / _samples;
      final double x = cx - (span / 2) + (span * t);
      // One asymmetric cycle — a shallow dip into a tall peak. A pure sine
      // reads as a logo for an oscilloscope; this reads as a voice.
      final double y =
          cy -
          amplitude *
              math.sin(t * 2 * math.pi) *
              (0.55 + 0.45 * math.sin(t * math.pi));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = TasukeColors.onPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * _strokeFraction
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
