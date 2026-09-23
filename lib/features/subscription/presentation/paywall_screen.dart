import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/subscription/data/subscription_providers.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

/// The paywall.
///
/// ⚠️ Several elements here exist because Apple 3.1.2 and Play's subscription
/// policy require them, not because the design sheet drew them — the period,
/// the auto-renew disclosure, the per-month equivalent, Restore Purchases on
/// this screen (not only in Settings), both legal links, and a dismiss control
/// with a real tap target. Missing any of them is the single most common cause
/// of a subscription app being rejected. Do not "tidy" them away.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({this.reason, super.key});

  /// Why the paywall is up. Null when the user opened it themselves, from
  /// Settings → Subscription or the Usage screen; those need no explanation.
  final PaywallReason? reason;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selectedId;
  bool _busy = false;

  /// Whether the user was Pro at the last value this screen saw.
  ///
  /// ⚠️ Seeded from the gateway in [initState], not from the listener's
  /// `previous`: the provider's first value follows `loading`, so a
  /// subscriber's silent launch restore landing here looks like a fresh
  /// purchase. Nor from `gateway.current` inside the listener, which already
  /// holds the new value by the time it fires.
  bool _wasPro = false;

  /// Set on the first welcome. A restore answer holding both plans sends two
  /// Pro values, and a second pop would close the screen underneath.
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _wasPro = ref.read(purchaseGatewayProvider).current.isPro;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SubscriptionPlan>> plans = ref.watch(
      subscriptionPlansProvider,
    );
    final bool isPro = ref.watch(isProProvider);
    // ⚠️ The reason alone is not proof. On iOS `tasuke:///paywall?reason=quota`
    // is a link anyone can send (FlutterDeepLinkingEnabled hands it straight
    // to go_router), and it told a free user with the day's capture unused
    // that it was spent. Until today's usage has loaded the reason stands:
    // the mic set it from a read a moment ago, and a line that popped in a
    // frame late would shove the whole page down. Usage is read only while
    // the reason is up, so a paywall opened from Settings never touches it.
    final bool quotaSpent =
        widget.reason == PaywallReason.quota &&
        !isPro &&
        (ref.watch(todayUsageProvider).value?.captureCount ??
                ExtractionDefaults.freeDailyCaptures) >=
            ExtractionDefaults.freeDailyCaptures;

    ref.listen<AsyncValue<Entitlement>>(entitlementProvider, (
      AsyncValue<Entitlement>? previous,
      AsyncValue<Entitlement> next,
    ) {
      final Entitlement? value = next.value;
      if (value == null) return;
      final bool becamePro = value.isPro && !_wasPro;
      _wasPro = value.isPro;
      if (becamePro && !_left) {
        _left = true;
        AppSnack.success(context, context.l10n.paywallPurchased);
        if (context.mounted) {
          context.canPop() ? context.pop() : context.go(AppRoute.home.path);
        }
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
                  // ⚠️ The mic sends a free user here once the day's capture
                  // is spent. Without this line they met a generic "Unlock
                  // your full potential" page and no word of why the mic had
                  // not opened; store/REVIEW_NOTES.md also tells App Review
                  // it is here.
                  if (quotaSpent) ...<Widget>[
                    TasukeBanner(
                      icon: Icons.today_rounded,
                      message: context.l10n.paywallQuotaHeader(
                        // Up only at the limit (`quotaSpent`), which is what
                        // `checkQuota` sends a user here at, and no sooner.
                        ExtractionDefaults.freeDailyCaptures,
                        ExtractionDefaults.freeDailyCaptures,
                      ),
                    ),
                    const SizedBox(height: TasukeSpacing.xl),
                  ],
                  CrownHeader(
                    title: context.l10n.paywallTitle,
                    subtitle: context.l10n.paywallSubtitle,
                  ),
                  const SizedBox(height: TasukeSpacing.xxl),
                  // ⚠️ Only what Pro really unlocks, and nothing a free user
                  // already has. The daily capture limit is the one gate in
                  // the app (`checkQuota`); several tasks from one capture
                  // and the extraction itself are the same for everyone.
                  // Apple 3.1.2 and Play both require the benefits of a
                  // subscription to be described accurately.
                  BenefitRow(label: context.l10n.paywallBenefitUnlimited),
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
                      if (isPro) return _manageSubscription();
                      final List<SubscriptionPlan> available =
                          plans.value ?? const <SubscriptionPlan>[];
                      if (available.isEmpty) return;
                      final SubscriptionPlan plan = available.firstWhere(
                        (SubscriptionPlan p) =>
                            p.id == (_selectedId ?? available.first.id),
                        orElse: () => available.first,
                      );
                      setState(() => _busy = true);
                      try {
                        await ref.read(purchaseGatewayProvider).buy(plan);
                      } on Object catch (error, stack) {
                        // Offline, Play services restarting, an unfinished
                        // StoreKit transaction: the sheet never opened.
                        Log.e('purchase could not start', error, stack);
                        if (context.mounted) {
                          AppSnack.error(
                            context,
                            context.l10n.paywallStoreUnavailableBody,
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
                  ),
                  const SizedBox(height: TasukeSpacing.md),
                  TextLinkButton(
                    label: context.l10n.paywallRestore,
                    onPressed: () async {
                      final PurchaseGateway gateway = ref.read(
                        purchaseGatewayProvider,
                      );
                      try {
                        await gateway.restore();
                      } on Object catch (error, stack) {
                        Log.e('restore failed', error, stack);
                        if (context.mounted) {
                          AppSnack.error(
                            context,
                            context.l10n.paywallStoreUnavailableBody,
                          );
                        }
                        return;
                      }
                      if (!context.mounted) return;
                      // The gateway, not isProProvider: that one only catches
                      // up once the stream event has travelled through it.
                      AppSnack.info(
                        context,
                        gateway.current.isPro
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

  /// ⚠️ Never a purchase. On Play the other plan is a separate subscription:
  /// buying it while one is active bills the user for both, and buying the
  /// same one fails as already owned. Switching and cancelling live on the
  /// store's own page.
  Future<void> _manageSubscription() async {
    final Uri page = ProductIds.manageUri(
      apple:
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS,
      productId: ref.read(purchaseGatewayProvider).current.productId,
    );
    final bool opened = await ref.read(storePageOpenerProvider).open(page);
    if (!opened && mounted) {
      AppSnack.error(context, context.l10n.paywallStoreUnavailableBody);
    }
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

    // ⚠️ Stacked, one full-width card per plan — not side by side. Two cards
    // in a Row gave each half a phone, and on a real device the store's price
    // wrapped as "$4. / 99" and the title as "Monthl / y".
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < plans.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: TasukeSpacing.cardGap),
          PlanCard(
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
        ],
      ],
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
