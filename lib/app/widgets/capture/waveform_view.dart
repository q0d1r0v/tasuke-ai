import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';

/// The live input meter on the Recording screen.
///
/// ⚠️ This is the one widget in the app where "rebuild" versus "repaint" is a
/// frame-rate decision rather than a style one. The recorder emits an amplitude
/// roughly every 50 ms; driving that through a provider rebuilds the Recording
/// screen 20 times a second, and the orb, the timer and the Stop button are
/// rebuilt with it. So the samples arrive as a [Listenable] handed straight to
/// the painter's `repaint:`, and this widget's `build` runs once.
class WaveformView extends StatelessWidget {
  const WaveformView({
    required this.amplitude,
    required this.samplesOf,
    this.barCount = 32,
    this.height = 64,
    super.key,
  });

  /// Ticks when there is a new sample. Never rebuilds this widget.
  final Listenable amplitude;

  /// The most recent levels, oldest first, each 0…1. Read inside `paint`, so
  /// the list is never copied into widget state.
  final List<double> Function() samplesOf;

  final int barCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            repaint: amplitude,
            samplesOf: samplesOf,
            barCount: barCount,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required Listenable repaint,
    required this.samplesOf,
    required this.barCount,
  }) : super(repaint: repaint);

  final List<double> Function() samplesOf;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 0 || size.width <= 0) return;

    final List<double> samples = samplesOf();
    final double slot = size.width / barCount;
    final double barWidth = slot * 0.5;
    final double radius = barWidth / 2;
    final double centreY = size.height / 2;
    // A bar is never invisible: a silent mic still draws the idle comb, which
    // is what tells the user the screen is live rather than frozen.
    final double minBar = barWidth;

    final Paint idle = Paint()..color = TasukeColors.waveformIdle;
    final Paint live = Paint()..color = TasukeColors.primary;

    for (int i = 0; i < barCount; i++) {
      // The newest sample is drawn at the right edge, so the comb reads as a
      // tape running past a playhead rather than as a bar chart.
      final int sampleIndex = samples.length - barCount + i;
      final double level = sampleIndex >= 0 && sampleIndex < samples.length
          ? samples[sampleIndex].clamp(0.0, 1.0)
          : 0.0;

      final double barHeight = minBar + ((size.height - minBar) * level);
      final double x = (slot * i) + ((slot - barWidth) / 2);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centreY - (barHeight / 2), barWidth, barHeight),
          Radius.circular(radius),
        ),
        level > 0 ? live : idle,
      );
    }
  }

  // The repaint Listenable drives every frame; there is nothing in a rebuild
  // that could also have changed.
  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.barCount != barCount || old.samplesOf != samplesOf;
}
