import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/features/model_setup/presentation/model_setup_providers.dart';

/// Offers the one-time language-model download.
///
/// ⚠️ Skippable by design. The app is fully usable without the model — manual
/// tasks, reminders, every screen — and only voice capture waits. A first
/// launch that is nothing but a progress bar is both bad retention and an App
/// Review "minimum functionality" risk.
class ModelSetupScreen extends ConsumerWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ModelState state = ref.watch(currentExtractorModelStateProvider);
    const ModelSpec spec = TasukeModels.extractor;

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter),
          child: Column(
            children: <Widget>[
              const Spacer(),
              const GradientOrb(size: 170),
              const SizedBox(height: TasukeSpacing.huge),
              Text(
                switch (state) {
                  ModelReady() => context.l10n.modelSetupReady,
                  ModelFailed() => context.l10n.modelSetupFailed,
                  _ => context.l10n.modelSetupTitle,
                },
                style: TasukeTypography.displayMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TasukeSpacing.md),
              Text(
                switch (state) {
                  final ModelFailed failed => failed.message,
                  ModelDownloading(:final int percent) =>
                    context.l10n.modelSetupProgress(percent),
                  _ => context.l10n.modelSetupSubtitle(spec.sizeLabel),
                },
                style: TasukeTypography.bodyMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TasukeSpacing.xxl),
              if (state is ModelDownloading)
                ClipRRect(
                  borderRadius: TasukeRadii.rPill,
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 8,
                  ),
                ),
              const Spacer(flex: 2),
              Text(
                context.l10n.modelSetupWifiHint,
                style: TasukeTypography.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TasukeSpacing.lg),
              PrimaryButton(
                label: switch (state) {
                  ModelDownloading() => context.l10n.modelSetupProgress(
                    (state).percent,
                  ),
                  ModelFailed() => context.l10n.actionRetry,
                  _ => context.l10n.modelSetupDownload,
                },
                busy: state is ModelDownloading,
                onPressed: state is ModelDownloading
                    ? null
                    : () => ref.read(modelInstallerProvider).install(spec),
              ),
              const SizedBox(height: TasukeSpacing.md),
              TextLinkButton(
                label: state is ModelDownloading
                    ? context.l10n.actionCancel
                    : context.l10n.modelSetupLater,
                onPressed: () {
                  if (state is ModelDownloading) {
                    ref.read(modelInstallerProvider).cancel(spec);
                    return;
                  }
                  context.go(AppRoute.home.path);
                },
              ),
              const SizedBox(height: TasukeSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
