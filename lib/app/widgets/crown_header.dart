import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/icon_tile.dart';

/// The paywall's masthead: crown, "Tasuke Pro", "Unlock your full potential".
class CrownHeader extends StatelessWidget {
  const CrownHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const IconTile(
          icon: Icon(Icons.workspace_premium_rounded),
          background: TasukeColors.goldTint,
          foreground: TasukeColors.gold,
        ),
        const SizedBox(height: TasukeSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TasukeTypography.displayMd,
          ),
        ),
        const SizedBox(height: TasukeSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TasukeTypography.bodyMd.copyWith(color: TasukeColors.inkMuted),
        ),
      ],
    );
  }
}
