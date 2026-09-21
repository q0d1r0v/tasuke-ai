import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// A spinner with something to read while it spins.
class LoadingState extends StatelessWidget {
  const LoadingState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TasukeSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: TasukeSpacing.xxl,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: TasukeSpacing.lg),
              Semantics(
                // The whole point of the message is that a screen reader says
                // it while nothing is happening visually.
                liveRegion: true,
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TasukeTypography.bodyMd.copyWith(
                    color: TasukeColors.inkMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
