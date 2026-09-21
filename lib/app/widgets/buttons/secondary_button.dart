import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/button_shell.dart';
import 'package:tasuke_ai/app/widgets/buttons/primary_button.dart';

/// The quiet twin of [PrimaryButton]: white, hairlined, no shadow.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.expanded = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return ButtonShell(
      semanticLabel: label,
      onPressed: onPressed,
      fill: TasukeColors.surface,
      side: const BorderSide(color: TasukeColors.border),
      expanded: expanded,
      child: ButtonLabel(
        label: label,
        style: TasukeTypography.button.copyWith(
          color: enabled ? TasukeColors.inkBody : TasukeColors.inkFaint,
        ),
      ),
    );
  }
}
