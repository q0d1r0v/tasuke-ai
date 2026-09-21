import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/primary_button.dart';
import 'package:tasuke_ai/app/widgets/icon_tile.dart';

/// "Nothing for today", "No tasks match…".
///
/// Every list in the app is empty on first launch, so this is the screen most
/// new users actually see first.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
    super.key,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.xl),
        child: Column(
          // min, so the state is as tall as its words and no taller — which is
          // what lets it sit inside a scroll view at 2× type scale without an
          // overflow stripe.
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              IconTile(icon: Icon(icon)),
              const SizedBox(height: TasukeSpacing.lg),
            ],
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
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: TasukeSpacing.xl),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
