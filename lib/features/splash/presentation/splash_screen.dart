import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/bootstrap/app_reset.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_gradients.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

/// The brand splash, held until [appBootstrapProvider] resolves.
///
/// No spinner: the wait is normally a few hundred milliseconds, and a spinner
/// over a brand mark reads as "something is wrong" rather than as "loading".
/// If the database cannot be opened this screen becomes the fatal-error screen
/// rather than handing the problem to a random list builder.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BootstrapResult> boot = ref.watch(appBootstrapProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: TasukeGradients.splash),
        child: SafeArea(
          child: Center(
            child: boot.hasError
                ? _FatalError(error: boot.error!)
                : const _Brand(),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const TasukeLogo(size: 96),
        const SizedBox(height: TasukeSpacing.xxl),
        Text(context.l10n.appTitle, style: TasukeTypography.wordmark),
        const SizedBox(height: TasukeSpacing.xs),
        Text(
          context.l10n.appSubtitle,
          style: TasukeTypography.bodyMd.copyWith(color: TasukeColors.inkMuted),
        ),
        const SizedBox(height: TasukeSpacing.xl),
        Text(context.l10n.appSlogan, style: TasukeTypography.bodySm),
      ],
    );
  }
}

/// Shown when the database will not open.
///
/// There is no backend, so "reset" really does mean losing the user's tasks —
/// which is why it is offered last, behind a confirmation, and never chosen
/// automatically.
class _FatalError extends ConsumerWidget {
  const _FatalError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const TasukeLogo(size: 72),
          const SizedBox(height: TasukeSpacing.xxl),
          Text(
            context.l10n.errorDatabaseTitle,
            style: TasukeTypography.titleMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TasukeSpacing.sm),
          Text(
            context.l10n.errorDatabaseBody,
            style: TasukeTypography.bodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: TasukeSpacing.xxl),
          PrimaryButton(
            label: context.l10n.actionRetry,
            onPressed: () => ref.invalidate(appBootstrapProvider),
          ),
          const SizedBox(height: TasukeSpacing.md),
          TextLinkButton(
            label: context.l10n.errorResetData,
            style: TasukeTypography.bodyMd.copyWith(color: TasukeColors.danger),
            onPressed: () async {
              final bool confirmed = await _confirmReset(context);
              if (!confirmed) return;
              await ref.read(databaseResetProvider)();
              ref.invalidate(appBootstrapProvider);
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmReset(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.settingsDeleteDataConfirmTitle),
        content: Text(context.l10n.settingsDeleteDataConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              context.l10n.actionDelete,
              style: const TextStyle(color: TasukeColors.danger),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
