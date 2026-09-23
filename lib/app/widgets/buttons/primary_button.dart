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
  ///
  /// ⚠️ Busy is a **working** state, not a disabled one. It stops taps; it does
  /// not fade the button. Painting it like a disabled control put a white
  /// spinner on `primaryWash` at 1.26:1 — an empty pale pill with a smudge in
  /// it, which reads as a crashed button. A caller that wants the faded look
  /// passes `onPressed: null`.
  final bool busy;

  final bool expanded;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    // Two different questions, and they used to share one answer.
    //   `interactive` — may it be tapped?   (busy blocks taps)
    //   `live`        — does it look alive? (only a null callback fades it)
    final bool interactive = onPressed != null && !busy;
    final bool live = onPressed != null;

    return ButtonShell(
      semanticLabel: label,
      onPressed: interactive ? onPressed : null,
      // primaryWash rather than primary-at-some-alpha: the palette already
      // carries the faded blue, and an inline alpha is a token nobody can find.
      fill: live ? TasukeColors.primary : TasukeColors.primaryWash,
      shadows: live ? TasukeShadows.button : null,
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
                color: live ? TasukeColors.onPrimary : TasukeColors.inkFaint,
              ),
            ),
          ),
          if (busy)
            SizedBox.square(
              dimension: TasukeSpacing.xl,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // White on the brand fill (3.8:1); on a faded fill the white
                // ring all but disappears, so the pressed blue is used instead.
                valueColor: AlwaysStoppedAnimation<Color>(
                  live ? TasukeColors.onPrimary : TasukeColors.primaryPressed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
