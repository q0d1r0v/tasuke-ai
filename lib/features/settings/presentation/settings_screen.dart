import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tasuke_ai/app/bootstrap/app_reset.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/model_setup/presentation/model_setup_providers.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppSettings> settings = ref.watch(appSettingsProvider);
    final bool isPro = ref.watch(isProProvider);
    final AsyncValue<DailyUsage> usage = ref.watch(todayUsageProvider);
    final AsyncValue<PackageInfo> info = ref.watch(packageInfoProvider);

    final AppSettings current = settings.value ?? AppSettings.defaults;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          TasukeSpacing.gutter,
          TasukeSpacing.lg,
          TasukeSpacing.gutter,
          TasukeMetrics.navBandHeightOf(context) + TasukeSpacing.lg,
        ),
        children: <Widget>[
          Text(context.l10n.settingsTitle, style: TasukeTypography.titleLg),
          const SizedBox(height: TasukeSpacing.xl),

          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                title: context.l10n.settingsNotifications,
                leading: const IconTile(
                  icon: Icon(Icons.notifications_none_rounded),
                ),
                showChevron: false,
                trailing: TasukeSwitch(
                  value: current.notificationsEnabled,
                  semanticLabel: context.l10n.settingsNotifications,
                  onChanged: (bool value) async {
                    await ref
                        .read(settingsRepositoryProvider)
                        .write(current.copyWith(notificationsEnabled: value));
                    // Turning the switch off is a kill switch, not a filter:
                    // the sweep cancels everything the OS is holding so the
                    // user stops being interrupted immediately.
                    await ref.read(reminderSchedulerProvider).sync();
                  },
                ),
              ),
              SettingsRow(
                title: context.l10n.settingsLanguage,
                leading: const IconTile(icon: Icon(Icons.language_rounded)),
                trailing: Text(
                  context.l10n.settingsLanguageEnglish,
                  style: TasukeTypography.label,
                ),
                onTap: () => context.push(AppRoute.language.path),
              ),
              SettingsRow(
                title: context.l10n.settingsSubscription,
                leading: const IconTile(
                  icon: Icon(Icons.workspace_premium_outlined),
                ),
                trailing: Text(
                  isPro
                      ? context.l10n.settingsSubscriptionPro
                      : context.l10n.settingsSubscriptionFree,
                  style: TasukeTypography.label,
                ),
                onTap: () => context.push(AppRoute.paywall.path),
              ),
              // ⚠️ The one way back to the model download after skipping it.
              //
              // `/model-setup` is offered once during first run and the router
              // bounces you off it afterwards, so without this row a user who
              // tapped "Not now" could never enable voice capture at all — and
              // the review notes promise this row exists.
              SettingsRow(
                title: context.l10n.settingsAiModel,
                leading: const IconTile(
                  icon: Icon(Icons.auto_awesome_outlined),
                ),
                trailing: Text(switch (ref.watch(
                  currentExtractorModelStateProvider,
                )) {
                  ModelReady() => context.l10n.settingsAiModelReady,
                  ModelDownloading(:final int percent) =>
                    context.l10n.modelSetupProgress(percent),
                  _ => context.l10n.settingsAiModelMissing,
                }, style: TasukeTypography.label),
                onTap: () => context.push(AppRoute.modelSetup.path),
              ),
              SettingsRow(
                title: context.l10n.settingsUsage,
                leading: const IconTile(icon: Icon(Icons.bar_chart_rounded)),
                isLast: true,
                trailing: Text(
                  isPro
                      ? context.l10n.settingsUsageUnlimited
                      : context.l10n.settingsUsageValue(
                          usage.value?.captureCount ?? 0,
                          ExtractionDefaults.freeDailyCaptures,
                        ),
                  style: TasukeTypography.label,
                ),
                onTap: () => context.push(AppRoute.usage.path),
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.xl),

          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                title: context.l10n.settingsRestorePurchases,
                leading: const IconTile(icon: Icon(Icons.restore_rounded)),
                showChevron: false,
                onTap: () async {
                  await ref.read(purchaseGatewayProvider).restore();
                  if (!context.mounted) return;
                  AppSnack.info(context, context.l10n.paywallRestoredNone);
                },
              ),
              SettingsRow(
                title: context.l10n.settingsPrivacyPolicy,
                leading: const IconTile(icon: Icon(Icons.privacy_tip_outlined)),
                onTap: () => context.push(AppRoute.privacy.path),
              ),
              SettingsRow(
                title: context.l10n.settingsTerms,
                leading: const IconTile(icon: Icon(Icons.description_outlined)),
                onTap: () => context.push(AppRoute.terms.path),
              ),
              SettingsRow(
                title: context.l10n.settingsHelp,
                leading: const IconTile(icon: Icon(Icons.help_outline_rounded)),
                onTap: () => context.push(AppRoute.help.path),
              ),
              SettingsRow(
                title: context.l10n.settingsAbout,
                leading: const IconTile(icon: Icon(Icons.info_outline_rounded)),
                isLast: true,
                trailing: Text(
                  context.l10n.aboutVersion(info.value?.version ?? '1.0.0'),
                  style: TasukeTypography.label,
                ),
                onTap: () => context.push(AppRoute.about.path),
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.xl),

          SettingsGroup(
            children: <Widget>[
              SettingsRow(
                title: context.l10n.settingsDeleteData,
                leading: const IconTile(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: TasukeColors.danger,
                  ),
                  background: TasukeColors.dangerTint,
                  foreground: TasukeColors.danger,
                ),
                showChevron: false,
                isLast: true,
                onTap: () async {
                  final bool confirmed =
                      await showDeleteAllDataDialog(context) ?? false;
                  if (!confirmed) return;
                  await ref.read(databaseResetProvider)();
                  if (!context.mounted) return;
                  AppSnack.success(
                    context,
                    context.l10n.settingsDeleteDataDone,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: TasukeSpacing.xxl),
          Text(
            context.l10n.aboutBuiltFor,
            style: TasukeTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// `package_info_plus` is a platform channel, so it is read once and cached
/// rather than awaited in a build method.
final FutureProvider<PackageInfo> packageInfoProvider =
    FutureProvider<PackageInfo>((Ref ref) => PackageInfo.fromPlatform());
