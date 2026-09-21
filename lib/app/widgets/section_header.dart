import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';

/// "Tomorrow", "Later", "Last 7 days" — the label above a group of rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TasukeSpacing.sectionGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(label, style: TasukeTypography.sectionHeader),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
