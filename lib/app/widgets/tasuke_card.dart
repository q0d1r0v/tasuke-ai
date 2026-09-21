import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';

/// The white rounded surface every list row, plan, task and settings group sits
/// on.
///
/// Intrinsic height by construction — it wraps whatever it is given and nothing
/// here pins a height. A card that is told how tall to be is the sibling app's
/// overflow bug at 2× type scale.
class TasukeCard extends StatelessWidget {
  const TasukeCard({
    required this.child,
    this.padding = const EdgeInsets.all(TasukeSpacing.lg),
    this.onTap,
    this.radius = TasukeRadii.card,
    this.elevated = true,
    this.background,
    this.border,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  /// Draws [TasukeShadows.card]. False for a card inside another card, or for
  /// one on a white sheet where the blue shadow would read as dirt.
  final bool elevated;

  final Color? background;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.all(Radius.circular(radius));

    Widget content = Padding(padding: padding, child: child);

    if (onTap != null) {
      // Only wrapped when tappable: an InkWell with a null onTap still installs
      // a gesture arena member, and the one over a task list row is enough to
      // swallow the list's own drag on some frames.
      content = Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(borderRadius: shape, onTap: onTap, child: content),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? TasukeColors.surface,
        borderRadius: shape,
        boxShadow: elevated ? TasukeShadows.card : null,
        border: border,
      ),
      child: content,
    );
  }
}
