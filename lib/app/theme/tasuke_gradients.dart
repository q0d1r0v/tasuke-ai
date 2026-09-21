import 'package:flutter/widgets.dart';

import 'tasuke_colors.dart';

/// The two gradients in the design sheet, named so no call site builds one
/// inline and drifts.
abstract final class TasukeGradients {
  /// The app icon, the mic button, the Recording orb, the Processing orb.
  /// Sampled top-left → bottom-right.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[TasukeColors.gradientStart, TasukeColors.gradientEnd],
  );

  /// The splash backdrop: a soft blue wash that fades to the canvas.
  static const LinearGradient splash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      TasukeColors.splashTint,
      TasukeColors.canvas,
      TasukeColors.surface,
    ],
    stops: <double>[0, 0.55, 1],
  );

  /// The halo behind the Recording screen's mic orb — the brand blue fading to
  /// nothing, painted as concentric rings.
  static const RadialGradient micHalo = RadialGradient(
    colors: <Color>[Color(0x332B7FFF), Color(0x0D2B7FFF), Color(0x002B7FFF)],
    stops: <double>[0, 0.6, 1],
  );
}
