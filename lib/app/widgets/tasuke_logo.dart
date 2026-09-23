import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// The app mark: a rounded gradient tile with a white voice trace inside it.
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
        painter: const TasukeLogoPainter(),
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

/// Draws the mark.
///
/// ⚠️ Public, and the **only** definition of the logo's geometry anywhere in
/// the repo. `tool/generate_icons.dart` renders this same painter to
/// `assets/images/icon.png`, `icon_foreground.png`, `icon_rounded.png` and
/// `splash_logo.png`, which is what guarantees that the launcher icon, the OS
/// splash and the in-app logo are the same drawing. The user sees the launcher
/// icon and the in-app logo within a second of each other on every cold start,
/// and two marks that are nearly the same read as the wrong app.
///
/// Regenerate after any change here:
///
/// ```
/// flutter test tool/generate_icons.dart
/// dart run flutter_launcher_icons
/// dart run flutter_native_splash:create
/// ```
class TasukeLogoPainter extends CustomPainter {
  const TasukeLogoPainter({
    this.drawTile = true,
    this.markScale = 1,
    this.roundedTile = true,
  });

  /// False for the Android adaptive foreground, which supplies its own
  /// background colour and must not carry a second tile inside the mask.
  final bool drawTile;

  /// False for the iOS app icon and the store listings: iOS and both stores
  /// apply their own corner mask, and a tile that is already rounded leaves the
  /// flattened (white) corners showing inside it.
  final bool roundedTile;

  /// Scales the whole drawing about the canvas centre.
  ///
  /// The adaptive icon is cropped to roughly the inner two thirds of its
  /// canvas, so the foreground is drawn at [adaptiveSafeScale] to survive the
  /// mask on a circular launcher.
  final double markScale;

  /// What fits inside every adaptive-icon mask Android ships.
  static const double adaptiveSafeScale = 0.66;

  /// The design grid the path below is expressed in, matching
  /// `design/tasuke_ai_logo.svg` one-to-one so the two can be diffed by eye.
  static const double _grid = 512;

  /// Tile corner radius, as a fraction of the tile.
  static const double _cornerFraction = 0.225;

  /// Stroke weight of the trace, in grid units (38 / 512).
  static const double _strokeGridUnits = 38;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect tile = Offset.zero & size;

    if (markScale != 1) {
      canvas
        ..save()
        ..translate(size.width / 2, size.height / 2)
        ..scale(markScale)
        ..translate(-size.width / 2, -size.height / 2);
    }

    if (drawTile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          tile,
          Radius.circular(roundedTile ? size.width * _cornerFraction : 0),
        ),
        Paint()..shader = TasukeGradients.brand.createShader(tile),
      );
    }

    final double kx = size.width / _grid;
    final double ky = size.height / _grid;

    // One continuous stroke that dips, climbs into a tall peak, falls through
    // a trough and lifts again — a voice trace, not an oscilloscope sine. The
    // asymmetry is what makes it read as speech.
    final Path path = Path()
      ..moveTo(128 * kx, 270 * ky)
      ..cubicTo(145 * kx, 270 * ky, 157 * kx, 252 * ky, 169 * kx, 230 * ky)
      ..lineTo(205 * kx, 165 * ky)
      ..cubicTo(218 * kx, 142 * ky, 249 * kx, 144 * ky, 260 * kx, 168 * ky)
      ..lineTo(306 * kx, 287 * ky)
      ..cubicTo(314 * kx, 307 * ky, 339 * kx, 311 * ky, 352 * kx, 294 * ky)
      ..lineTo(386 * kx, 249 * ky);

    canvas.drawPath(
      path,
      Paint()
        ..color = TasukeColors.onPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * (_strokeGridUnits / _grid)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    if (markScale != 1) canvas.restore();
  }

  @override
  bool shouldRepaint(TasukeLogoPainter oldDelegate) =>
      oldDelegate.drawTile != drawTile || oldDelegate.markScale != markScale;
}
