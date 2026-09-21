import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/tasks/check_circle.dart';

/// One line of the paywall's benefit list.
class BenefitRow extends StatelessWidget {
  const BenefitRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TasukeSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The same tick the task list draws, with no callback — which is what
          // strips its 48pt tap box and its semantics action, leaving a glyph.
          const CheckCircle(checked: true, onChanged: null),
          const SizedBox(width: TasukeSpacing.md),
          Expanded(child: Text(label, style: TasukeTypography.bodyMd)),
        ],
      ),
    );
  }
}
