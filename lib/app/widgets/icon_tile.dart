import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';

/// The rounded square behind a glyph, on Permissions, Task Details and Settings.
class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    this.background = TasukeColors.primaryTint,
    this.foreground = TasukeColors.primary,
    this.size = TasukeMetrics.iconTile,
    this.radius = TasukeRadii.tile,
    super.key,
  });

  /// A widget, not an [IconData], so a tile can hold a painted glyph — the Pro
  /// crown and the logo mark are not font icons.
  final Widget icon;

  final Color background;
  final Color foreground;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      // The tile carries the colour and the size so call sites pass a bare
      // `Icon(Icons.mic)` and cannot tint it wrong.
      child: IconTheme.merge(
        data: IconThemeData(color: foreground, size: size * 0.5),
        child: Center(child: icon),
      ),
    );
  }
}
