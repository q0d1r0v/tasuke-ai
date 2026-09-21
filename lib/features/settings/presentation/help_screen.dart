import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> topics = <(String, String)>[
      (context.l10n.helpHowToTitle, context.l10n.helpHowToBody),
      (context.l10n.helpOfflineTitle, context.l10n.helpOfflineBody),
      (context.l10n.helpRemindersTitle, context.l10n.helpRemindersBody),
    ];

    return TasukeScaffold(
      title: context.l10n.helpTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (String title, String body) in topics) ...<Widget>[
            TasukeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TasukeTypography.titleSm),
                  const SizedBox(height: TasukeSpacing.sm),
                  Text(body, style: TasukeTypography.bodyMd),
                ],
              ),
            ),
            const SizedBox(height: TasukeSpacing.cardGap),
          ],
        ],
      ),
    );
  }
}
