import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/buttons/tasuke_switch.dart';
import 'package:tasuke_ai/app/widgets/section_header.dart';
import 'package:tasuke_ai/app/widgets/tasuke_card.dart';

/// One row inside a [SettingsGroup].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.isLast = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// A value, a [TasukeSwitch], a badge. Replaces the chevron when
  /// [showChevron] is false.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool showChevron;

  /// Suppresses this row's bottom hairline. [SettingsGroup] sets it on the last
  /// row for you; it is only passed by hand for a row standing on its own.
  final bool isLast;

  /// Widgets are data, which is what lets [SettingsGroup] hand the final row a
  /// copy of itself with the separator off instead of making 40 call sites
  /// remember `isLast`.
  SettingsRow _copyAsLast() => SettingsRow(
    key: key,
    title: title,
    subtitle: subtitle,
    leading: leading,
    trailing: trailing,
    onTap: onTap,
    showChevron: showChevron,
    isLast: true,
  );

  @override
  Widget build(BuildContext context) {
    final Widget content = ConstrainedBox(
      // A minimum: a row with a subtitle at 2× type scale is taller than the
      // design's 64pt and must be allowed to grow.
      constraints: const BoxConstraints(minHeight: TasukeMetrics.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TasukeSpacing.lg,
          vertical: TasukeSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: TasukeSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(title, style: TasukeTypography.bodyLg),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: TasukeSpacing.xs / 2),
                    Text(subtitle!, style: TasukeTypography.caption),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: TasukeSpacing.sm),
              // Flexible so a long trailing value wraps instead of overflowing
              // the row at a large type scale.
              Flexible(child: trailing!),
            ],
            if (showChevron && onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: TasukeSpacing.xs),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: TasukeSpacing.xl,
                  color: TasukeColors.inkFaint,
                ),
              ),
          ],
        ),
      ),
    );

    final Widget row = onTap == null
        ? content
        : Material(
            type: MaterialType.transparency,
            // A middle row really is square; the group's ClipRRect rounds the
            // first and last. Clipping here as well costs nothing and keeps a
            // row used outside a group from squaring off its own corners.
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: content),
          );

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          row,
          if (!isLast)
            const Padding(
              // Indented to the text, not to the card edge: the design
              // separates rows without boxing them.
              padding: EdgeInsets.only(left: TasukeSpacing.lg),
              child: Divider(height: 1),
            ),
        ],
      ),
    );
  }
}

/// A card that hairlines its rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, this.header, super.key});

  final List<Widget> children;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      for (int i = 0; i < children.length; i++)
        if (i == children.length - 1 && children[i] is SettingsRow)
          (children[i] as SettingsRow)._copyAsLast()
        else
          children[i],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (header != null) SectionHeader(label: header!),
        TasukeCard(
          padding: EdgeInsets.zero,
          // Clipped so a row's ink splash and its hairline both stop at the
          // card's corner instead of squaring it off.
          child: ClipRRect(
            borderRadius: TasukeRadii.rCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}
