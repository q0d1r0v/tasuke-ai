import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/screen_header.dart';

/// Page chrome, defined once.
///
/// Every screen in the app is this: the canvas, a safe area, the gutter, an
/// optional [ScreenHeader] and an optional pinned bottom bar.
class TasukeScaffold extends StatelessWidget {
  const TasukeScaffold({
    required this.child,
    this.title,
    this.showBack = false,
    this.actions = const <Widget>[],
    this.scrollable = true,
    this.bottomBar,
    this.padding,
    super.key,
  });

  final Widget child;
  final String? title;
  final bool showBack;
  final List<Widget> actions;

  /// ⚠️ With `scrollable: true` the child is laid out with unbounded height, so
  /// it may not contain an `Expanded`, a `Spacer` or a second vertical
  /// viewport. Screens that need those pass `false` and manage their own.
  final bool scrollable;

  /// A CTA pinned under the content — Confirm's "Save Tasks", Paywall's
  /// "Subscribe".
  ///
  /// ⚠️ Laid out inside the body, NOT as `Scaffold.bottomNavigationBar`. That
  /// slot is hit-tested before the body, so anything opaque in it eats taps on
  /// the bottom of the content while every navigation test still passes. Being
  /// in the body also means `resizeToAvoidBottomInset` lifts it above the
  /// keyboard instead of the keyboard covering it.
  final Widget? bottomBar;

  /// Overrides the content inset. The default is the gutter on both sides.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final bool hasHeader = title != null || showBack || actions.isNotEmpty;
    final EdgeInsets contentPadding =
        padding ?? const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter);

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (hasHeader)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TasukeSpacing.sm,
                  vertical: TasukeSpacing.xs,
                ),
                child: ScreenHeader(
                  title: title ?? '',
                  onBack: showBack
                      ? () => unawaited(Navigator.maybePop<void>(context))
                      : null,
                  trailing: actions.isEmpty
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: actions),
                ),
              ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(padding: contentPadding, child: child)
                  : Padding(padding: contentPadding, child: child),
            ),
            if (bottomBar != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentPadding.left,
                  TasukeSpacing.md,
                  contentPadding.right,
                  TasukeSpacing.md,
                ),
                child: bottomBar,
              ),
          ],
        ),
      ),
    );
  }
}
