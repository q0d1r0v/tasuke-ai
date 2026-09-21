import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// Every confirmation the app can raise, in one file.
///
/// They all resolve to `true` for "do it", `false` for "don't" and **null** for
/// dismissed-by-tapping-outside. Call sites must treat null as "don't": a
/// `== true` check is the only safe test, and `!= false` deletes the user's
/// tasks when they tap the scrim.
Future<bool?> showDiscardDraftsDialog(BuildContext context) => _confirm(
  context,
  title: context.l10n.confirmDiscardTitle,
  message: context.l10n.confirmDiscardBody,
  confirmLabel: context.l10n.confirmDiscardConfirm,
);

Future<bool?> showDeleteTaskDialog(BuildContext context) => _confirm(
  context,
  title: context.l10n.taskDeleteConfirmTitle,
  message: context.l10n.taskDeleteConfirmBody,
  confirmLabel: context.l10n.actionDelete,
);

/// After a database failure, on the "Tasuke can't open its database" screen.
Future<bool?> showResetDataDialog(BuildContext context) => _confirm(
  context,
  title: context.l10n.errorResetData,
  message: context.l10n.settingsDeleteDataConfirmBody,
  confirmLabel: context.l10n.actionContinue,
);

Future<bool?> showDeleteAllDataDialog(BuildContext context) => _confirm(
  context,
  title: context.l10n.settingsDeleteDataConfirmTitle,
  message: context.l10n.settingsDeleteDataConfirmBody,
  confirmLabel: context.l10n.actionDelete,
);

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title, style: TasukeTypography.titleSm),
        content: Text(message, style: TasukeTypography.bodyMd),
        // Cancel first, destructive second: the reading order the platform
        // conventions put it in, and the one where the thumb's resting
        // position is not over the irreversible option.
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              dialogContext.l10n.actionCancel,
              style: TasukeTypography.button.copyWith(
                color: TasukeColors.inkMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TasukeTypography.button.copyWith(
                color: TasukeColors.danger,
              ),
            ),
          ),
        ],
      );
    },
  );
}
