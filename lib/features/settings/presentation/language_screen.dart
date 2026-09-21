import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

/// Language selection.
///
/// v1 ships English only, and this screen says so rather than not existing:
/// the design sheet has a Language row, and a row that opens nothing is worse
/// than a screen with one option. Every string in the app already goes through
/// the ARB, so adding a locale is a translation file and one entry here.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TasukeScaffold(
      title: context.l10n.languageTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                title: context.l10n.settingsLanguageEnglish,
                leading: const IconTile(icon: Icon(Icons.language_rounded)),
                showChevron: false,
                isLast: true,
                trailing: const Icon(
                  Icons.check_rounded,
                  color: TasukeColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.lg),
        ],
      ),
    );
  }
}
