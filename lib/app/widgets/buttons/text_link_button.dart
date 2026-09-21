import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// A text-only action: "Skip", "Restore Purchases", "Not now".
class TextLinkButton extends StatelessWidget {
  const TextLinkButton({
    required this.label,
    required this.onPressed,
    this.style,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final TextStyle resolved = (style ?? TasukeTypography.bodyLg).copyWith(
      color: enabled
          ? (style?.color ?? TasukeColors.primary)
          : TasukeColors.inkFaint,
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: TasukeRadii.rField,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: TasukeRadii.rField,
            onTap: onPressed,
            // A link is still a tap target: the design draws bare text, so the
            // 48pt box has to be added here or the hit area is 19pt tall.
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TasukeMetrics.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TasukeSpacing.md,
                ),
                child: Center(
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: resolved,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
