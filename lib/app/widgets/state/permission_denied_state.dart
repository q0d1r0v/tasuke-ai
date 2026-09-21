import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/primary_button.dart';
import 'package:tasuke_ai/app/widgets/icon_tile.dart';
import 'package:tasuke_ai/app/widgets/state/error_state.dart';

/// The microphone (or notifications) were refused.
///
/// Separate from [ErrorState] because the copy and the button both depend on
/// whether the OS will prompt again: the caller passes "Allow" or "Open
/// Settings", and offering a retry that the OS silently ignores is the bug this
/// screen exists to prevent.
class PermissionDeniedState extends StatelessWidget {
  const PermissionDeniedState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const IconTile(icon: Icon(Icons.mic_off_rounded)),
            const SizedBox(height: TasukeSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TasukeTypography.titleSm,
            ),
            const SizedBox(height: TasukeSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TasukeTypography.bodyMd.copyWith(
                color: TasukeColors.inkMuted,
              ),
            ),
            const SizedBox(height: TasukeSpacing.xl),
            PrimaryButton(
              label: actionLabel,
              onPressed: onAction,
              expanded: false,
            ),
          ],
        ),
      ),
    );
  }
}
