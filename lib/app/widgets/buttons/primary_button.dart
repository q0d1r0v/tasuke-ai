import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/button_shell.dart';

/// The app's one filled call to action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.expanded = true,
    this.leading,
    super.key,
  });

  final String label;

  /// `null` disables the button: faded fill, no shadow, no ink.
  final VoidCallback? onPressed;

  /// Swaps the label for a spinner **without changing the button's width**, and
  /// stops taps.
  ///
  /// ⚠️ The label stays in the layout behind `Opacity(0)` rather than being
  /// replaced. Replacing it re-measures the button, a non-expanded CTA jumps to
  /// the spinner's width mid-tap, and the user's second tap lands on whatever
  /// moved underneath — which is how a double purchase happens.
  final bool busy;

  final bool expanded;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;

    return ButtonShell(
      semanticLabel: label,
      onPressed: enabled ? onPressed : null,
      // primaryWash rather than primary-at-some-alpha: the palette already
      // carries the faded blue, and an inline alpha is a token nobody can find.
      fill: enabled ? TasukeColors.primary : TasukeColors.primaryWash,
      shadows: enabled ? TasukeShadows.button : null,
      expanded: expanded,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Opacity(
            opacity: busy ? 0 : 1,
            child: ButtonLabel(
              label: label,
              leading: leading,
              style: TasukeTypography.button.copyWith(
                color: enabled ? TasukeColors.onPrimary : TasukeColors.inkFaint,
              ),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: TasukeSpacing.xl,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  TasukeColors.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
