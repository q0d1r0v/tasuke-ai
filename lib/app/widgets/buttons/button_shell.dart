import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/buttons/danger_button.dart';
import 'package:tasuke_ai/app/widgets/buttons/primary_button.dart';
import 'package:tasuke_ai/app/widgets/buttons/secondary_button.dart';

/// The shared chrome behind [PrimaryButton], [SecondaryButton] and
/// [DangerButton].
///
/// Deliberately not part of the catalogue's advertised surface: it exists so the
/// three CTAs cannot drift in height, corner radius, ink shape or semantics.
/// They differ only in fill, label colour, border and shadow.
class ButtonShell extends StatelessWidget {
  const ButtonShell({
    required this.semanticLabel,
    required this.onPressed,
    required this.fill,
    required this.expanded,
    required this.child,
    this.shadows,
    this.side,
    super.key,
  });

  /// Announced instead of [child]'s own text.
  ///
  /// ⚠️ The label cannot be read off the child: a busy [PrimaryButton] hides its
  /// text behind `Opacity(0)`, and `RenderOpacity` drops the semantics of a
  /// fully transparent subtree. Without this the button would go silent to a
  /// screen reader at exactly the moment it is doing something.
  final String semanticLabel;

  final VoidCallback? onPressed;
  final Color fill;
  final bool expanded;
  final Widget child;
  final List<BoxShadow>? shadows;
  final BorderSide? side;

  @override
  Widget build(BuildContext context) {
    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: TasukeRadii.rButton,
        boxShadow: shadows,
        border: side == null ? null : Border.fromBorderSide(side!),
      ),
      // Transparency, not a coloured Material: the fill and the shadow are the
      // DecoratedBox's, and a second opaque layer would paint over the shadow's
      // inner edge.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: TasukeRadii.rButton,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: TasukeRadii.rButton,
          onTap: onPressed,
          child: ConstrainedBox(
            // A minimum, never a fixed height. At TextScaler 2.0 the label is
            // taller than the design's 54pt control and a SizedBox clips it —
            // which is the overflow that shipped in the sibling app.
            constraints: const BoxConstraints(
              minHeight: TasukeMetrics.controlHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TasukeSpacing.xl,
                vertical: TasukeSpacing.sm,
              ),
              // widthFactor 1 makes a non-expanded button hug its label:
              // without it Center takes the parent's full width, because the
              // constraints handed down are loose rather than unbounded.
              child: Center(
                widthFactor: expanded ? null : 1,
                child: ExcludeSemantics(child: child),
              ),
            ),
          ),
        ),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        child: expanded
            ? SizedBox(width: double.infinity, child: surface)
            : surface,
      ),
    );
  }
}

/// The label + optional leading glyph every CTA lays out.
class ButtonLabel extends StatelessWidget {
  const ButtonLabel({
    required this.label,
    required this.style,
    this.leading,
    super.key,
  });

  final String label;
  final TextStyle style;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      label,
      style: style,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (leading == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Sized off the label rather than off a constant, so the glyph keeps
        // its optical relationship to the text at every type scale.
        Icon(
          leading,
          size: (style.fontSize ?? TasukeSpacing.lg) * 1.25,
          color: style.color,
        ),
        const SizedBox(width: TasukeSpacing.sm),
        // Flexible, not Expanded: in a min-size Row an Expanded child demands
        // an unbounded share and throws.
        Flexible(child: text),
      ],
    );
  }
}
