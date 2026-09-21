import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// Transient confirmations: "Task deleted", "2 tasks saved", "Something went
/// wrong".
///
/// ⚠️ Nothing here takes a transcript or a task title. A snack bar is the one
/// surface that outlives the screen that raised it, and `Log.redact` exists for
/// the same reason.
abstract final class AppSnack {
  static void info(BuildContext context, String message) =>
      _show(context, message, TasukeColors.ink, Icons.info_outline_rounded);

  static void success(BuildContext context, String message) => _show(
    context,
    message,
    TasukeColors.success,
    Icons.check_circle_outline_rounded,
  );

  static void error(BuildContext context, String message) =>
      _show(context, message, TasukeColors.danger, Icons.error_outline_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color background,
    IconData icon,
  ) {
    ScaffoldMessenger.of(context)
      // Hidden first, not queued. Two saves in a row otherwise leave the second
      // confirmation waiting four seconds behind the first, long after the
      // screen it belonged to has gone.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: background,
          margin: const EdgeInsets.all(TasukeSpacing.lg),
          content: Row(
            children: <Widget>[
              Icon(icon, color: TasukeColors.onPrimary, size: TasukeSpacing.xl),
              const SizedBox(width: TasukeSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: TasukeTypography.bodyMd.copyWith(
                    color: TasukeColors.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
