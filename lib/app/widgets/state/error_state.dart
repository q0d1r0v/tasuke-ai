import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/primary_button.dart';
import 'package:tasuke_ai/app/widgets/buttons/text_link_button.dart';
import 'package:tasuke_ai/app/widgets/icon_tile.dart';

/// A failure the user can do something about.
///
/// [onRetry] is required and [actionLabel] with it: an error screen whose
/// button does nothing is worse than one with no button, and making them
/// optional is how that ships.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.title,
    required this.actionLabel,
    required this.onRetry,
    this.message,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String? message;
  final String actionLabel;
  final VoidCallback onRetry;

  /// The way out that is not a retry — "Type a task instead", "Open Settings".
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const IconTile(
              icon: Icon(Icons.error_outline_rounded),
              background: TasukeColors.dangerTint,
              foreground: TasukeColors.danger,
            ),
            const SizedBox(height: TasukeSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TasukeTypography.titleSm,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: TasukeSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TasukeTypography.bodyMd.copyWith(
                  color: TasukeColors.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: TasukeSpacing.xl),
            PrimaryButton(
              label: actionLabel,
              onPressed: onRetry,
              expanded: false,
            ),
            if (secondaryLabel != null && onSecondary != null) ...<Widget>[
              const SizedBox(height: TasukeSpacing.xs),
              TextLinkButton(label: secondaryLabel!, onPressed: onSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
