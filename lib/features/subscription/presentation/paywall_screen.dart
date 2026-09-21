import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/subscription/data/subscription_providers.dart';

/// The paywall.
///
/// ⚠️ Several elements here exist because Apple 3.1.2 and Play's subscription
/// policy require them, not because the design sheet drew them — the period,
/// the auto-renew disclosure, the per-month equivalent, Restore Purchases on
/// this screen (not only in Settings), both legal links, and a dismiss control
/// with a real tap target. Missing any of them is the single most common cause
/// of a subscription app being rejected. Do not "tidy" them away.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selectedId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SubscriptionPlan>> plans = ref.watch(
      subscriptionPlansProvider,
    );
    final bool isPro = ref.watch(isProProvider);

    ref.listen<AsyncValue<Entitlement>>(entitlementProvider, (
      AsyncValue<Entitlement>? previous,
      AsyncValue<Entitlement> next,
    ) {
      final Entitlement? value = next.value;
      if (value == null) return;
      if (value.isPro) {
        AppSnack.success(context, context.l10n.paywallPurchased);
        if (context.mounted) context.pop();
      }
      if (value.status == EntitlementStatus.pending) {
        setState(() => _busy = false);
      }
    });

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: TasukeSpacing.sm),
                child: IconButton(
                  // ⚠️ A paywall you cannot leave is a rejection on Apple's
                  // side and a dark pattern on Google's. 48pt target.
                  iconSize: 24,
                  padding: const EdgeInsets.all(12),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: context.l10n.actionClose,
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoute.home.path),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: TasukeSpacing.gutter,
                ),
                children: <Widget>[
                  CrownHeader(
                    title: context.l10n.paywallTitle,
                    subtitle: context.l10n.paywallSubtitle,
                  ),
                  const SizedBox(height: TasukeSpacing.xxl),
                  BenefitRow(label: context.l10n.paywallBenefitUnlimited),
                  BenefitRow(label: context.l10n.paywallBenefitMultiple),
                  BenefitRow(label: context.l10n.paywallBenefitAdvanced),
                  BenefitRow(label: context.l10n.paywallBenefitPriority),
                  BenefitRow(label: context.l10n.paywallBenefitSupport),
                  const SizedBox(height: TasukeSpacing.xxl),
                  plans.when(
                    loading: () => const LoadingState(),
                    error: (Object error, StackTrace stack) => ErrorState(
                      title: context.l10n.paywallStoreUnavailableTitle,
                      message: context.l10n.paywallStoreUnavailableBody,
                      actionLabel: context.l10n.actionRetry,
                      onRetry: () => ref.invalidate(subscriptionPlansProvider),
                    ),
                    data: (List<SubscriptionPlan> available) {
                      if (available.isEmpty) {
                        return ErrorState(
                          title: context.l10n.paywallStoreUnavailableTitle,
                          message: context.l10n.paywallStoreUnavailableBody,
                          actionLabel: context.l10n.actionRetry,
                          onRetry: () =>
                              ref.invalidate(subscriptionPlansProvider),
                        );
                      }
                      return _Plans(
                        plans: available,
                        selectedId: _selectedId ?? available.first.id,
                        onSelected: (String id) =>
                            setState(() => _selectedId = id),
                      );
                    },
                  ),
                  const SizedBox(height: TasukeSpacing.lg),
                  Text(
                    context.l10n.paywallFreeTierNote(
                      ExtractionDefaults.freeDailyCaptures,
                    ),
                    style: TasukeTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TasukeSpacing.md),
                  Text(
                    context.l10n.paywallAutoRenewNotice,
                    style: TasukeTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TasukeSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: TasukeSpacing.lg,
                    children: <Widget>[
                      TextLinkButton(
                        label: context.l10n.settingsTerms,
                        style: TasukeTypography.caption,
                        onPressed: () => context.push(AppRoute.terms.path),
                      ),
                      TextLinkButton(
                        label: context.l10n.settingsPrivacyPolicy,
                        style: TasukeTypography.caption,
                        onPressed: () => context.push(AppRoute.privacy.path),
                      ),
                    ],
                  ),
                  const SizedBox(height: TasukeSpacing.xxl),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TasukeSpacing.gutter,
                0,
                TasukeSpacing.gutter,
                TasukeSpacing.xl,
              ),
              child: Column(
                children: <Widget>[
                  PrimaryButton(
                    label: isPro
                        ? context.l10n.paywallManage
                        : context.l10n.paywallSubscribe,
                    busy: _busy,
                    onPressed: () async {
                      final List<SubscriptionPlan> available =
                          plans.value ?? const <SubscriptionPlan>[];
                      if (available.isEmpty) return;
                      final SubscriptionPlan plan = available.firstWhere(
                        (SubscriptionPlan p) =>
                            p.id == (_selectedId ?? available.first.id),
                        orElse: () => available.first,
                      );
                      setState(() => _busy = true);
                      await ref.read(purchaseGatewayProvider).buy(plan);
                      if (mounted) setState(() => _busy = false);
                    },
                  ),
                  const SizedBox(height: TasukeSpacing.md),
                  TextLinkButton(
                    label: context.l10n.paywallRestore,
                    onPressed: () async {
                      await ref.read(purchaseGatewayProvider).restore();
                      if (!context.mounted) return;
                      AppSnack.info(
                        context,
                        ref.read(isProProvider)
                            ? context.l10n.paywallRestored
                            : context.l10n.paywallRestoredNone,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  const _Plans({
    required this.plans,
    required this.selectedId,
    required this.onSelected,
  });

  final List<SubscriptionPlan> plans;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final SubscriptionPlan? monthly = plans
        .where((SubscriptionPlan p) => p.period == SubscriptionPeriod.monthly)
        .firstOrNull;

    // ⚠️ `IntrinsicHeight` is load-bearing, not decoration. The paywall hosts
    // this Row inside a ListView, where the cross-axis constraint is unbounded,
    // and `CrossAxisAlignment.stretch` then hands each card an infinite height
    // — which throws "BoxConstraints forces an infinite height" and leaves the
    // plans, the disclosure and the legal links unrendered. Stretch is what
    // makes the two cards match heights when one carries a badge and a
    // footnote, so the height is bounded here rather than the alignment
    // dropped.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < plans.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: TasukeSpacing.cardGap),
            Expanded(
              child: PlanCard(
                title: plans[i].period == SubscriptionPeriod.yearly
                    ? context.l10n.paywallYearly
                    : context.l10n.paywallMonthly,
                // ⚠️ From the store, never a literal: a hardcoded "$4.99" shows
                // the wrong currency to most of the world.
                price: plans[i].price,
                period: plans[i].period == SubscriptionPeriod.yearly
                    ? context.l10n.paywallPeriodYear
                    : context.l10n.paywallPeriodMonth,
                badge: _badge(context, plans[i], monthly),
                footnote: _footnote(context, plans[i], monthly),
                selected: plans[i].id == selectedId,
                onTap: () => onSelected(plans[i].id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _badge(
    BuildContext context,
    SubscriptionPlan plan,
    SubscriptionPlan? monthly,
  ) {
    if (plan.period != SubscriptionPeriod.yearly || monthly == null) {
      return null;
    }
    final double yearOfMonthly = monthly.rawPrice * 12;
    if (yearOfMonthly <= 0) return null;
    final int percent = (100 - (plan.rawPrice / yearOfMonthly * 100)).round();
    return percent > 0 ? context.l10n.paywallSave(percent) : null;
  }

  String? _footnote(
    BuildContext context,
    SubscriptionPlan plan,
    SubscriptionPlan? monthly,
  ) {
    if (plan.period != SubscriptionPeriod.yearly) return null;
    // Required by both stores: the per-unit price of a longer term.
    final double perMonth = plan.rawPrice / 12;
    return context.l10n.paywallYearlyEquivalent(
      '${plan.currencyCode} ${perMonth.toStringAsFixed(2)}',
    );
  }
}
