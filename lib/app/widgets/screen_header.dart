import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// A screen's title row: optional back affordance, centred title, optional
/// trailing action.
///
/// Not an [AppBar]. The design's title sits on the canvas with no surface, no
/// elevation and no scroll-under tint, and every one of those is something an
/// AppBar has to be argued out of.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: TasukeMetrics.minTapTarget),
      child: Row(
        children: <Widget>[
          // Fixed, equal side slots. Without them the title is centred in the
          // space left over by the back button and drifts sideways between a
          // screen that has one and a screen that does not.
          SizedBox(
            width: TasukeMetrics.minTapTarget,
            child: onBack == null
                ? null
                : IconButton(
                    onPressed: onBack,
                    iconSize: TasukeSpacing.xl,
                    color: TasukeColors.ink,
                    // The ARB has no "Back": this one string is Flutter's own,
                    // already translated in every locale the framework ships,
                    // and IconButton turns a tooltip into the semantics label.
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TasukeTypography.titleMd,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            width: TasukeMetrics.minTapTarget,
            child: trailing == null
                ? null
                : Align(alignment: Alignment.centerRight, child: trailing),
          ),
        ],
      ),
    );
  }
}
