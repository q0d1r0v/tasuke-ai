import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';

/// The four bottom-nav destinations plus the mic button.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onMicTap: () async {
          final CaptureController capture = ref.read(
            captureControllerProvider.notifier,
          );
          // Held rather than looked up after the await: once the wait below
          // has moved the user to /capture, this shell is gone and so is its
          // context.
          final GoRouter router = GoRouter.of(context);
          bool waited = false;
          final String? destination = await capture.begin(
            // ⚠️ When the last capture is still letting go of the speech
            // model, `begin` can take up to half a minute: a capture cancelled
            // after Stop finishes whisper's final pass first. Navigating only
            // once it returned left Home looking exactly as it did before the
            // tap. The phase is still `checkingQuota`, which /capture shows as
            // "Getting ready" with a Cancel.
            //
            // Called only once the quota has passed, so a user who has spent
            // the day's capture goes straight to the paywall, with no capture
            // screen flashed up on the way.
            onWait: () {
              waited = true;
              router.go(AppRoute.capture.path);
            },
          );
          if (destination == null) return;
          if (!waited && !context.mounted) return;

          // ⚠️ `go` for the capture flow, never `push`. This one line was the
          // whole of "Finishing up... for three minutes".
          //
          // The capture screens are not navigated to by the screens themselves:
          // the router's redirect watches the pipeline's phase and moves
          // /capture -> /capture/processing -> /capture/confirm as it advances.
          // But go_router hands a top-level redirect the BASE location of the
          // match list, and a pushed page is not the base. After
          // `push('/capture')` the redirect saw "/home", its capture rule never
          // matched, and the phase advanced — transcript done, tasks extracted
          // — underneath a Recording screen that could never leave. Whisper
          // had finished in seconds; the user was waiting on a route.
          //
          // `go` makes /capture the base, so the redirect sees it. Nothing is
          // lost by dropping Home from the stack: every capture screen owns its
          // back gesture with `PopScope(canPop: false)` and returns to /home
          // itself.
          if (destination.startsWith(kCapturePathPrefix)) {
            router.go(destination);
          } else {
            // The paywall is a sheet the user closes back to where they were.
            // Its location carries the reason (`?reason=quota`), which is what
            // puts "You've used today's free capture." at its top.
            unawaited(router.push<void>(destination));
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
