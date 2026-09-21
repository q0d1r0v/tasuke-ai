import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/settings/presentation/settings_screen.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PackageInfo> info = ref.watch(packageInfoProvider);

    return TasukeScaffold(
      title: context.l10n.settingsAbout,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: TasukeSpacing.lg),
          const Center(child: TasukeLogo(size: 80)),
          const SizedBox(height: TasukeSpacing.lg),
          Center(
            child: Text(context.l10n.appTitle, style: TasukeTypography.titleMd),
          ),
          Center(
            child: Text(
              context.l10n.aboutVersion(info.value?.version ?? '1.0.0'),
              style: TasukeTypography.caption,
            ),
          ),
          const SizedBox(height: TasukeSpacing.xxl),
          TasukeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.aboutOnDeviceTitle,
                  style: TasukeTypography.titleSm,
                ),
                const SizedBox(height: TasukeSpacing.sm),
                Text(
                  context.l10n.aboutOnDeviceBody,
                  style: TasukeTypography.bodyMd,
                ),
              ],
            ),
          ),
          const SizedBox(height: TasukeSpacing.xl),
          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                title: context.l10n.aboutLicenses,
                leading: const IconTile(icon: Icon(Icons.article_outlined)),
                isLast: true,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: context.l10n.appTitle,
                  applicationVersion: info.value?.version ?? '1.0.0',
                ),
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.xxl),
          Center(
            child: Text(
              context.l10n.appSlogan,
              style: TasukeTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}
