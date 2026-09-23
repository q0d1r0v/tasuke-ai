import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isPro = ref.watch(isProProvider);
    final DailyUsage usage =
        ref.watch(todayUsageProvider).value ??
        DailyUsage.empty(ref.watch(todayProvider));
    const int limit = ExtractionDefaults.freeDailyCaptures;

    return TasukeScaffold(
      title: context.l10n.usageTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TasukeCard(
            child: Column(
              children: <Widget>[
                Text(
                  isPro
                      ? context.l10n.settingsUsageUnlimited
                      : '${usage.captureCount} / $limit',
                  style: TasukeTypography.price,
                ),
                const SizedBox(height: TasukeSpacing.xs),
                Text(
                  context.l10n.settingsUsage,
                  style: TasukeTypography.caption,
                ),
                if (!isPro) ...<Widget>[
                  const SizedBox(height: TasukeSpacing.lg),
                  ClipRRect(
                    borderRadius: TasukeRadii.rPill,
                    child: LinearProgressIndicator(
                      value: (usage.captureCount / limit).clamp(0.0, 1.0),
                      minHeight: 8,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: TasukeSpacing.xl),
          if (!isPro)
            PrimaryButton(
              label: context.l10n.quotaSeeProPlans,
              onPressed: () => context.push(AppRoute.paywall.path),
            ),
        ],
      ),
    );
  }
}
