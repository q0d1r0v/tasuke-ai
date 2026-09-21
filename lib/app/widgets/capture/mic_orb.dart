import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/capture/waveform_view.dart';

/// The Recording screen's breathing mic orb.
///
/// Takes a [Listenable] and a getter rather than a level, for the same reason
/// [WaveformView] does: the amplitude changes tens of times a second and a
/// provider rebuild at that rate rebuilds the whole screen.
class MicOrb extends StatefulWidget {
  const MicOrb({
    required this.amplitude,
    required this.levelOf,
    this.size = TasukeMetrics.micOrb,
    super.key,
  });

  final Listenable amplitude;

  /// 0…1. Clamped here, because a recorder that reports -160 dB on the first
  /// frame would otherwise collapse the rings inside out.
  final double Function() levelOf;

  final double size;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: TasukeDurations.orbPulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double core = widget.size * 0.55;

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable?>[widget.amplitude, _breath]),
        // The core is passed as `child` so the gradient circle and its icon are
        // built once and only the rings are repainted on each tick.
        child: Center(
          child: Container(
            width: core,
            height: core,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: TasukeGradients.brand,
              boxShadow: TasukeShadows.fab,
            ),
            child: Icon(
              Icons.mic_rounded,
              color: TasukeColors.onPrimary,
              size: core * 0.44,
            ),
          ),
        ),
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _OrbPainter(
              level: widget.levelOf().clamp(0.0, 1.0),
              breath: _breath.value,
              coreRadius: core / 2,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.level,
    required this.breath,
    required this.coreRadius,
  });

  final double level;
  final double breath;
  final double coreRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double outer = size.shortestSide / 2;

    // The halo never leaves the box: at level 1 and full breath the widest ring
    // is exactly the widget's radius, so an orb in a Column cannot overflow it.
    final double reach =
        coreRadius +
        ((outer - coreRadius) * (0.55 + (0.3 * level) + (0.15 * breath)));

    canvas.drawCircle(
      centre,
      reach,
      Paint()
        ..shader = TasukeGradients.micHalo.createShader(
          Rect.fromCircle(center: centre, radius: reach),
        ),
    );

    for (int ring = 0; ring < 2; ring++) {
      final double t = (ring + 1) / 3;
      canvas.drawCircle(
        centre,
        coreRadius + ((reach - coreRadius) * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = TasukeColors.primary.withValues(
            alpha: 0.28 * (1 - t) * (0.5 + (0.5 * level)),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.level != level ||
      old.breath != breath ||
      old.coreRadius != coreRadius;
}
