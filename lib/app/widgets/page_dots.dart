import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';

/// The onboarding pager's position indicator.
class PageDots extends StatelessWidget {
  const PageDots({required this.count, required this.index, super.key});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    // Decoration. The page's own heading is what a screen reader should read,
    // and "dot, dot, dot" ahead of it is noise — announcing the position would
    // also need an ARB key the app does not have.
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TasukeSpacing.xs / 2,
              ),
              child: AnimatedContainer(
                duration: TasukeDurations.fast,
                curve: Curves.easeOut,
                // The active dot WIDENS. Recolouring alone is invisible to the
                // 8% of men who cannot separate these two blues.
                width: i == index ? TasukeSpacing.xl : TasukeSpacing.sm,
                height: TasukeSpacing.sm,
                decoration: BoxDecoration(
                  color: i == index
                      ? TasukeColors.primary
                      : TasukeColors.outlineSoft,
                  borderRadius: TasukeRadii.rPill,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
