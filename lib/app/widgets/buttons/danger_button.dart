import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/button_shell.dart';

/// The destructive CTA, in the design's two flavours.
///
/// `filled: true` is Recording's "Stop" — a solid red button the thumb aims at.
/// `filled: false` is Task Details' "Delete Task" — a tinted row the user has to
/// mean, which is why the loud version is not the default.
class DangerButton extends StatelessWidget {
  const DangerButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.leading,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color labelColor = filled
        ? TasukeColors.onPrimary
        : TasukeColors.danger;

    return ButtonShell(
      semanticLabel: label,
      onPressed: onPressed,
      fill: filled ? TasukeColors.danger : TasukeColors.dangerTint,
      expanded: true,
      child: ButtonLabel(
        label: label,
        leading: leading,
        style: TasukeTypography.button.copyWith(
          color: enabled ? labelColor : TasukeColors.inkFaint,
        ),
      ),
    );
  }
}
