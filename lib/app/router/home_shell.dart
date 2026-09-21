import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/features/model_setup/presentation/model_setup_providers.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';

/// The four bottom-nav destinations plus the mic button.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ModelState model = ref.watch(currentExtractorModelStateProvider);

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      // The nav band floats over the list, so the body must extend under it and
      // each screen adds `TasukeMetrics.navBandHeightOf(context)` of bottom
      // padding to its own scroll view.
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: TasukeBottomNav(
        currentIndex: navigationShell.currentIndex,
        onSelected: (int index) => navigationShell.goBranch(
          index,
          // Tapping the tab you are already on pops that branch to its root —
          // the standard gesture, and free here.
          initialLocation: index == navigationShell.currentIndex,
        ),
        micEnabled: model is ModelReady || model is ModelNotInstalled,
        micProgressLabel: model is ModelDownloading
            ? context.l10n.modelSetupPreparing(model.percent)
            : null,
        onMicTap: () async {
          final String? destination = await ref
              .read(captureControllerProvider.notifier)
              .begin();
          if (destination != null && context.mounted) {
            unawaited(context.push<void>(destination));
          }
        },
      ),
    );
  }
}

/// go_router's fallback. Reachable only through a malformed deep link, but a
/// blank screen there is indistinguishable from a crash.
class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TasukeSpacing.gutter,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  context.l10n.errorGenericTitle,
                  style: TasukeTypography.titleMd,
                ),
                const SizedBox(height: TasukeSpacing.sm),
                Text(
                  location,
                  style: TasukeTypography.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TasukeSpacing.xxl),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: Text(context.l10n.actionGotIt),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
