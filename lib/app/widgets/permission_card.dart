import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/icon_tile.dart';
import 'package:tasuke_ai/app/widgets/tasuke_card.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';

/// A permission the app is asking for, with its current answer.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final PermissionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool granted = state.isGranted;

    return TasukeCard(
      // A granted permission has nothing left to ask: the card stops being a
      // button so a second tap cannot open a system prompt that never appears.
      onTap: granted ? null : onTap,
      child: MergeSemantics(
        child: Row(
          children: <Widget>[
            IconTile(
              icon: icon,
              background: granted
                  ? TasukeColors.successTint
                  : TasukeColors.primaryTint,
              foreground: granted ? TasukeColors.success : TasukeColors.primary,
            ),
            const SizedBox(width: TasukeSpacing.md),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title, style: TasukeTypography.bodyLg),
                  const SizedBox(height: TasukeSpacing.xs / 2),
                  Text(subtitle, style: TasukeTypography.caption),
                ],
              ),
            ),
            const SizedBox(width: TasukeSpacing.sm),
            // Flexible and wrapping, never a fixed pill: "Open Settings" at 2×
            // type scale is wider than half the card.
            Flexible(flex: 2, child: _Status(state: state)),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});

  final PermissionState state;

  @override
  Widget build(BuildContext context) {
    if (state.isGranted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.check_circle_rounded,
            size: TasukeSpacing.xl,
            color: TasukeColors.success,
          ),
          const SizedBox(width: TasukeSpacing.xs),
          Flexible(
            child: Text(
              context.l10n.permissionsGranted,
              style: TasukeTypography.label.copyWith(
                color: TasukeColors.success,
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: TasukeColors.primaryTint,
          borderRadius: TasukeRadii.rPill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TasukeSpacing.md,
            vertical: TasukeSpacing.sm,
          ),
          child: Text(
            // permanentlyDenied and restricted cannot be answered by a prompt,
            // so the card sends the user where the answer actually lives.
            state.needsSettings
                ? context.l10n.actionOpenSettings
                : context.l10n.actionAllow,
            textAlign: TextAlign.center,
            style: TasukeTypography.label.copyWith(color: TasukeColors.primary),
          ),
        ),
      ),
    );
  }
}
