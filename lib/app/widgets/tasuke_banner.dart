import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// How loud a [TasukeBanner] is.
enum BannerTone { info, warning, danger }

/// An inline notice above a screen's content: notifications are off, reminders
/// may arrive late, this device delays alarms.
///
/// Inline and dismissible rather than a snack bar, because every one of those
/// messages is about a setting that is still wrong after the snack has gone.
class TasukeBanner extends StatelessWidget {
  const TasukeBanner({
    required this.message,
    this.icon,
    this.onDismiss,
    this.tone = BannerTone.info,
    super.key,
  });

  final String message;
  final IconData? icon;
  final VoidCallback? onDismiss;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color glyph) = switch (tone) {
      BannerTone.info => (TasukeColors.primaryTint, TasukeColors.primary),
      BannerTone.warning => (TasukeColors.goldTint, TasukeColors.gold),
      BannerTone.danger => (TasukeColors.dangerTint, TasukeColors.danger),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: TasukeRadii.rField,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TasukeSpacing.md,
          TasukeSpacing.md,
          TasukeSpacing.sm,
          TasukeSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon ?? Icons.info_outline_rounded,
              size: TasukeSpacing.xl,
              color: glyph,
            ),
            const SizedBox(width: TasukeSpacing.sm),
            Expanded(
              child: Padding(
                // Optically centres the text against the glyph without pinning
                // a height the text could outgrow.
                padding: const EdgeInsets.only(top: TasukeSpacing.xs / 2),
                child: Text(
                  message,
                  style: TasukeTypography.bodySm.copyWith(
                    color: TasukeColors.inkBody,
                  ),
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: context.l10n.actionDismiss,
                iconSize: TasukeSpacing.xl,
                color: TasukeColors.inkMuted,
                // The default 8pt visual density would drop the target under
                // 48pt; the banner is not tall enough to hide that.
                constraints: const BoxConstraints(
                  minWidth: TasukeMetrics.minTapTarget,
                  minHeight: TasukeMetrics.minTapTarget,
                ),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
