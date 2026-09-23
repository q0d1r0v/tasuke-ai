import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/purchases/store_purchase_gateway.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/subscription/presentation/paywall_screen.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The store-compliance surface.
///
/// ⚠️ Every disclosure asserted here is required by Apple 3.1.2 or by Play's
/// subscription policy, and a missing one is the single most common cause of a
/// subscription app being rejected. The fake store quotes tenge, with the
/// symbol behind the amount and a space inside it: a screen that renders those
/// exact strings is a screen that took them from the store rather than from a
/// literal somebody typed in dollars.
void main() {
  const SubscriptionPlan monthly = SubscriptionPlan(
    id: 'pro.monthly',
    title: 'Tasuke Pro Monthly',
    description: 'Unlimited voice capture',
    price: '₸2 490',
    rawPrice: 2490,
    currencyCode: 'KZT',
    period: SubscriptionPeriod.monthly,
  );
  const SubscriptionPlan yearly = SubscriptionPlan(
    id: 'pro.yearly',
    title: 'Tasuke Pro Yearly',
    description: 'Unlimited voice capture',
    price: '₸19 900',
    rawPrice: 19900,
    currencyCode: 'KZT',
    period: SubscriptionPeriod.yearly,
  );

  /// Wednesday 2026-03-11, 10:00 local.
  final Clock clock = FixedClock(DateTime(2026, 3, 11, 10));

  late FakePurchaseGateway store;
  late FakeStorePageOpener storePages;
  late FakeUsageRepository usage;

  setUp(() {
    store = FakePurchaseGateway(plans: <SubscriptionPlan>[monthly, yearly]);
    storePages = FakeStorePageOpener();
    usage = FakeUsageRepository();
  });

  tearDown(() {
    unawaited(store.dispose());
    usage.dispose();
  });

  /// Uses up the free captures of the day [clock] is pinned to.
  Future<void> spendToday() async {
    for (int i = 0; i < ExtractionDefaults.freeDailyCaptures; i++) {
      await usage.recordCapture(
        LocalDate.today(clock.nowLocal()),
        taskCount: 1,
      );
    }
  }

  /// Pumps the paywall the way the app reaches it: pushed on top of something.
  ///
  /// The dismiss control pops when it can, so a paywall pumped as the root
  /// route would exercise the fallback rather than the path every user takes.
  ///
  /// ⚠️ The smallest supported phone by default. Half of what this screen has
  /// to show exists for App Review, and 320×568 is where it stops fitting.
  ///
  /// [pushed] false opens the paywall as the only route, the way a deep link
  /// or a `go` reaches it. [reason] is what the mic passes once the day's
  /// capture is spent; null is Settings → Subscription.
  Future<void> pumpPaywall(
    WidgetTester tester, {
    PurchaseGateway? gateway,
    DeviceFrame frame = DeviceFrame.smallNoInsets,
    bool pushed = true,
    PaywallReason? reason,
  }) async {
    final String location = reason?.location ?? AppRoute.paywall.path;
    await tester.binding.setSurfaceSize(frame.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = GoRouter(
      initialLocation: pushed ? AppRoute.home.path : location,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoute.home.path,
          builder: (_, _) => const Scaffold(body: Center(child: Text('Home'))),
        ),
        // Built the way app_router.dart builds it: the reason comes from
        // the location, so this also proves it survives the trip.
        GoRoute(
          path: AppRoute.paywall.path,
          builder: (_, GoRouterState state) => PaywallScreen(
            reason: PaywallReason.fromQuery(state.uri.queryParameters),
          ),
        ),
        GoRoute(
          path: AppRoute.terms.path,
          builder: (_, _) => const Scaffold(body: Center(child: Text('EULA'))),
        ),
        GoRoute(
          path: AppRoute.privacy.path,
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('Privacy'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        // The paywall touches two ports — the store and the store's own
        // subscription page — and, only while it is up for a reason, today's
        // usage. A fake for a provider it never reads would only hide that.
        overrides: <Override>[
          purchaseGatewayProvider.overrideWithValue(gateway ?? store),
          storePageOpenerProvider.overrideWithValue(storePages),
          if (reason != null) ...<Override>[
            clockProvider.overrideWithValue(clock),
            usageRepositoryProvider.overrideWithValue(usage),
          ],
        ],
        child: MaterialApp.router(
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await pumpSettled(tester);

    if (!pushed) return;
    unawaited(router.push(location));
    await pumpSettled(tester);
  }

  /// Brings [target] into the paywall's own list.
  ///
  /// ⚠️ The disclosures below the plan cards do not fit above the fold on a
  /// 320×568 phone — the list is ~1200pt of content in a 386pt viewport — so
  /// what the stores actually require of this screen is that every one of them
  /// is present, reachable and rendered without clipping. That is what these
  /// tests assert, rather than a no-scroll layout the design cannot have.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpSettled(tester);
  }

  /// Asserts the widget is on the screen, not merely in the tree.
  void expectOnScreen(WidgetTester tester, Finder target) {
    expect(target, findsOneWidget);
    final Rect screen = tester.getRect(find.byType(MaterialApp));
    final Rect rect = tester.getRect(target);
    expect(rect.top, greaterThanOrEqualTo(screen.top - 0.5));
    expect(rect.bottom, lessThanOrEqualTo(screen.bottom + 0.5));
    expect(rect.left, greaterThanOrEqualTo(screen.left - 0.5));
    expect(rect.right, lessThanOrEqualTo(screen.right + 0.5));
  }

  group('the store-required disclosures', () {
    testWidgets('each plan states its title, its billing period and the '
        "store's own price string", (WidgetTester tester) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Yearly'));

      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);

      // The period, spelled out. "Yearly" alone does not tell a first-time
      // buyer what they are about to be charged for.
      expect(find.text('1 month'), findsOneWidget);
      expect(find.text('1 year'), findsOneWidget);

      // ⚠️ The exact strings the fake store handed over. A hardcoded "$4.99"
      // shows the wrong currency to most of the world and is a rejection.
      expect(find.text('₸2 490'), findsOneWidget);
      expect(find.text('₸19 900'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);

      expectOnScreen(tester, find.text('₸19 900'));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the yearly card carries a per-month equivalent and a saving '
        'computed from the two prices', (WidgetTester tester) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Yearly'));

      // 19 900 / 12, in the store's currency — required by both stores when a
      // longer term is offered beside a shorter one.
      expect(find.text('KZT 1658.33 per month, billed yearly'), findsOneWidget);
      // 19 900 against 12 × 2 490 = 29 880, so a third off.
      expect(find.text('Save 33%'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the monthly card claims no saving and no equivalent', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Monthly'));

      // A "Save 0%" badge on the plan the saving is measured against would be
      // a false claim about a price, and a per-month equivalent of a monthly
      // plan is just its price again.
      final PlanCard monthlyCard = tester.widget<PlanCard>(
        find.byType(PlanCard).first,
      );
      expect(monthlyCard.price, '₸2 490');
      expect(monthlyCard.badge, isNull);
      expect(monthlyCard.footnote, isNull);
      expect(find.textContaining('Save'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the auto-renew disclosure is on the paywall in full', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      final Finder notice = find.textContaining('renews automatically');
      await reveal(tester, notice);

      expect(
        find.text(
          'Subscription renews automatically unless cancelled at least 24 '
          'hours before the end of the current period. Payment is charged to '
          'your store account at confirmation of purchase.',
        ),
        findsOneWidget,
      );
      expectOnScreen(tester, notice);

      // What the free tier still includes, so "1 a day" is not a surprise
      // discovered after declining.
      expect(
        find.textContaining('Free: 1 capture a day, spoken or typed'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('both legal documents are linked from the paywall itself', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Terms of Service'));

      expectOnScreen(tester, find.text('Terms of Service'));
      expectOnScreen(tester, find.text('Privacy Policy'));

      await tester.tap(find.text('Terms of Service'));
      await pumpSettled(tester);
      expect(find.text('EULA'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Restore Purchases is on this screen, not only in Settings', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);

      // Pinned under the CTA, so it is reachable without hunting: a buyer on a
      // new device who cannot find it files a refund request instead.
      expectOnScreen(tester, find.text('Restore Purchases'));

      await tester.tap(find.text('Restore Purchases'));
      await pumpSettled(tester);

      expect(store.restoreCount, 1);
      expect(find.text('No previous purchase found'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the dismiss control is a 44pt target and really leaves', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);

      final Finder close = find.byType(IconButton);
      expectOnScreen(tester, close);
      final Size target = tester.getSize(close);
      // ⚠️ A paywall you cannot leave is a rejection on Apple's side and a
      // dark pattern on Google's. 44pt is the floor; this one draws 48.
      expect(target.width, greaterThanOrEqualTo(44));
      expect(target.height, greaterThanOrEqualTo(44));

      await tester.tap(close);
      await pumpSettled(tester);

      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(store.bought, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nothing on it overflows at 320pt wide', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);

      // Scrolling the whole list is what forces every child through layout on
      // the narrowest supported screen. An overflow or an unbounded constraint
      // is thrown as an exception, which fails the test by itself.
      await reveal(tester, find.text('Privacy Policy'));
      expect(find.byType(PaywallScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the states', () {
    testWidgets('a store that is not available says so rather than spinning', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway unavailable = FakePurchaseGateway(
        available: false,
        plans: <SubscriptionPlan>[monthly, yearly],
      );
      addTearDown(() => unawaited(unavailable.dispose()));

      await pumpPaywall(tester, gateway: unavailable);
      await reveal(tester, find.text("The store isn't available"));

      expect(
        find.text('Check your connection and store account, then try again.'),
        findsOneWidget,
      );
      // ⚠️ Not a spinner. The usual cause is an unsigned Paid Applications
      // agreement, which no amount of waiting fixes.
      expect(find.byType(LoadingState), findsNothing);
      expect(find.text('Monthly'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a store with no known products lands on the same message', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway empty = FakePurchaseGateway();
      addTearDown(() => unawaited(empty.dispose()));

      await pumpPaywall(tester, gateway: empty);
      await reveal(tester, find.text("The store isn't available"));

      // A product that came back in `notFoundIDs` is hidden, and a paywall
      // with no plans must explain itself rather than render a blank card.
      expect(find.byType(PlanCard), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Subscribe buys the selected plan and closes the sheet', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Yearly'));

      await tester.tap(find.text('Yearly'));
      await pumpSettled(tester);

      await tester.tap(find.text('Subscribe'));
      await pumpSettled(tester);

      expect(store.bought, <String>['pro.yearly']);
      // The entitlement arriving is what dismisses the paywall — the user is
      // Pro now, and leaving them looking at the offer is a support ticket.
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the first plan is preselected, so Subscribe is never a '
        'no-op', (WidgetTester tester) async {
      await pumpPaywall(tester);

      await tester.tap(find.text('Subscribe'));
      await pumpSettled(tester);

      expect(store.bought, <String>['pro.monthly']);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tapping Subscribe twice does not buy twice', (
      WidgetTester tester,
    ) async {
      final _PendingStore pending = _PendingStore(<SubscriptionPlan>[
        monthly,
        yearly,
      ]);
      addTearDown(() => unawaited(pending.dispose()));

      await pumpPaywall(tester, gateway: pending);

      await tester.tap(find.text('Subscribe'));
      await pumpSettled(tester);

      // The store's own sheet is up; the CTA is busy and must not re-enter.
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).busy,
        isTrue,
      );
      // ⚠️ `warnIfMissed: false` because missing is the assertion: a busy CTA
      // has no hit target, so this tap lands on the scaffold behind it.
      await tester.tap(find.text('Subscribe'), warnIfMissed: false);
      await pumpSettled(tester);

      expect(pending.bought, <String>['pro.monthly']);

      pending.settle();
      await pumpSettled(tester);
      expect(find.byType(PaywallScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a subscriber is offered management, not another purchase', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway pro = FakePurchaseGateway(
        plans: <SubscriptionPlan>[monthly, yearly],
        initial: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: 'pro.yearly',
        ),
      );
      addTearDown(() => unawaited(pro.dispose()));

      await pumpPaywall(tester, gateway: pro);

      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Subscribe'), findsNothing);

      // The other card, then the CTA: exactly how a monthly subscriber on Play
      // ended up paying for both plans at once.
      await reveal(tester, find.text('Monthly'));
      await tester.tap(find.text('Monthly'));
      await pumpSettled(tester);
      await tester.tap(find.text('Manage subscription'));
      await pumpSettled(tester);

      expect(pro.bought, isEmpty);
      // flutter_test runs as Android: the Play page for the plan held.
      expect(storePages.opened, <Uri>[
        ProductIds.manageUri(apple: false, productId: 'pro.yearly'),
      ]);
      expect(find.byType(PaywallScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a store page that will not open says so', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway pro = FakePurchaseGateway(
        plans: <SubscriptionPlan>[monthly, yearly],
        initial: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: 'pro.monthly',
        ),
      );
      addTearDown(() => unawaited(pro.dispose()));
      storePages.opens = false;

      await pumpPaywall(tester, gateway: pro);
      await tester.tap(find.text('Manage subscription'));
      await pumpSettled(tester);

      expect(
        find.text('Check your connection and store account, then try again.'),
        findsOneWidget,
      );
      expect(pro.bought, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a purchase that cannot start frees the button and says '
        'why', (WidgetTester tester) async {
      final _FailingStore failing = _FailingStore(<SubscriptionPlan>[
        monthly,
        yearly,
      ]);
      addTearDown(() => unawaited(failing.dispose()));

      await pumpPaywall(tester, gateway: failing);
      await tester.tap(find.text('Subscribe'));
      await pumpSettled(tester);

      // ⚠️ Not a spinner forever. Offline, Play re-queries the product to
      // nothing and `buy` throws before any sheet opens.
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).busy,
        isFalse,
      );
      expect(
        find.text('Check your connection and store account, then try again.'),
        findsOneWidget,
      );
      expect(find.byType(PaywallScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a restore the store cannot answer says so, rather than '
        '"nothing found"', (WidgetTester tester) async {
      final _FailingStore failing = _FailingStore(<SubscriptionPlan>[
        monthly,
        yearly,
      ]);
      addTearDown(() => unawaited(failing.dispose()));

      await pumpPaywall(tester, gateway: failing);
      await tester.tap(find.text('Restore Purchases'));
      await pumpSettled(tester);

      expect(
        find.text('Check your connection and store account, then try again.'),
        findsOneWidget,
      );
      expect(find.text('No previous purchase found'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('why it is up', () {
    const String quotaLine = "You've used today's free capture.";

    testWidgets("the mic's paywall says the day's capture is spent, first", (
      WidgetTester tester,
    ) async {
      // ⚠️ Every free user meets this from their second capture of a day.
      // It used to be the generic "Unlock your full potential" page, and
      // store/REVIEW_NOTES.md promised App Review a line it never showed.
      await spendToday();
      await pumpPaywall(tester, reason: PaywallReason.quota);

      expectOnScreen(tester, find.text(quotaLine));
      expect(
        tester.getRect(find.text(quotaLine)).bottom,
        lessThan(tester.getRect(find.text('Tasuke Pro')).top),
        reason: 'above the header, before anything else is read',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reached by `go` from a failure screen, it still says so', (
      WidgetTester tester,
    ) async {
      // The Recording screen's "Try again" goes to what `begin` returned.
      await spendToday();
      await pumpPaywall(tester, reason: PaywallReason.quota, pushed: false);

      expectOnScreen(tester, find.text(quotaLine));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a link that claims it, with the capture unused, is not '
        'believed', (WidgetTester tester) async {
      // ⚠️ iOS hands `tasuke:///paywall?reason=quota` to go_router
      // (FlutterDeepLinkingEnabled), and anyone can send one. The reason
      // alone told a user who had not captured anything today that they had
      // used today's capture.
      await pumpPaywall(tester, reason: PaywallReason.quota, pushed: false);

      expect(find.text(quotaLine), findsNothing);
      expect(find.byType(TasukeBanner), findsNothing);
      expect(find.text('Tasuke Pro'), findsOneWidget, reason: 'still up');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Settings → Subscription opens it with no such line', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      await reveal(tester, find.text('Privacy Policy'));

      expect(find.textContaining("You've used"), findsNothing);
      expect(find.byType(TasukeBanner), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a subscriber is never told they are out of captures', (
      WidgetTester tester,
    ) async {
      final FakePurchaseGateway pro = FakePurchaseGateway(
        plans: <SubscriptionPlan>[monthly, yearly],
        initial: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: 'pro.yearly',
        ),
      );
      addTearDown(() => unawaited(pro.dispose()));
      // Past the free allowance, so the subscription is the only difference.
      await spendToday();

      await pumpPaywall(tester, gateway: pro, reason: PaywallReason.quota);

      expect(find.text(quotaLine), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the benefits', () {
    testWidgets('promise only what Pro unlocks', (WidgetTester tester) async {
      // ⚠️ The daily capture limit is the one thing Pro changes. "Unlimited
      // voice processing" said only voice was limited, beside a free-tier
      // note saying spoken OR typed; "Multiple tasks from one voice input"
      // is free for everyone; there is no "Advanced AI processing", nor any
      // "Priority updates" — every user gets the same build from the store.
      // A benefit a buyer cannot find after paying is a 3.1.2 rejection and a
      // refund request.
      await pumpPaywall(tester);
      // Above the fold on the smallest phone, before any plan.
      expectOnScreen(tester, find.text('Unlimited captures, spoken or typed'));
      expectOnScreen(tester, find.text('Support the development'));
      expect(find.byType(BenefitRow, skipOffstage: false), findsNWidgets(2));
      for (final String untrue in <String>[
        'voice processing',
        'Multiple tasks',
        'Advanced AI',
        'Priority updates',
      ]) {
        expect(
          find.textContaining(untrue, skipOffstage: false),
          findsNothing,
          reason: untrue,
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the free allowance', () {
    // ⚠️ Typed tasks count against the daily capture too (a product decision,
    // 2026-09-23), so the paywall must not offer a typed task as a way round
    // it: the mic opens this screen once the day's capture is spent.
    testWidgets('offers no typed-task way round the quota', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester);
      await tester.scrollUntilVisible(
        find.text('Restore Purchases').last,
        120,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Type a task instead'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the welcome', () {
    const Entitlement proYearly = Entitlement(
      status: EntitlementStatus.proActive,
      productId: 'pro.yearly',
    );

    testWidgets('is not shown to a subscriber when the store confirms what '
        'they already had', (WidgetTester tester) async {
      // ⚠️ The silent launch restore can land while a subscriber is here to
      // manage their plan. Taken for a purchase, it welcomes them and closes
      // the screen under their finger.
      final FakePurchaseGateway pro = FakePurchaseGateway(
        plans: <SubscriptionPlan>[monthly, yearly],
        initial: proYearly,
      );
      addTearDown(() => unawaited(pro.dispose()));

      await pumpPaywall(tester, gateway: pro);
      pro.emit(proYearly);
      await pumpSettled(tester);

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Welcome to Tasuke Pro'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('is shown once, and closes the paywall once, when the answer '
        'holds both plans', (WidgetTester tester) async {
      await pumpPaywall(tester);

      // A user billed for both plans before "Manage" existed: one answer, two
      // Pro values. A second pop would close Home, or throw a GoError.
      store
        ..emit(
          const Entitlement(
            status: EntitlementStatus.proActive,
            productId: 'pro.monthly',
          ),
        )
        ..emit(proYearly);
      await pumpSettled(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Welcome to Tasuke Pro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('goes home when there is nothing to pop back to', (
      WidgetTester tester,
    ) async {
      await pumpPaywall(tester, pushed: false);

      store.emit(proYearly);
      await pumpSettled(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('on StoreKit, the launch restore', () {
    testWidgets('keeps a subscriber Pro on an empty answer, and only Restore '
        'revokes, saying "No previous purchase found"', (
      WidgetTester tester,
    ) async {
      // The real gateway, not the fake: what is under test is its launch
      // reconcile, seen through the paywall a subscriber then opens.
      final _OfflineStoreKit client = _OfflineStoreKit();
      final StorePurchaseGateway gateway = StorePurchaseGateway(
        client: client,
        store: _MemoryEntitlements(
          const Entitlement(
            status: EntitlementStatus.proActive,
            productId: ProductIds.monthly,
          ),
        ),
      );
      addTearDown(gateway.dispose);
      await gateway.initialise();
      await tester.pump();
      expect(client.restores, 1);
      expect(gateway.current.isPro, isTrue);

      await pumpPaywall(tester, gateway: gateway);
      expect(find.text('Manage subscription'), findsOneWidget);

      await tester.tap(find.text('Restore Purchases'));
      await pumpSettled(tester);

      // Two asks: the tap did not join a launch restore still in flight, so
      // the Pro kept above is the launch restore's own answer.
      expect(client.restores, 2);
      expect(gateway.current.isPro, isFalse);
      expect(find.text('No previous purchase found'), findsOneWidget);
      expect(
        find.text('Check your connection and store account, then try again.'),
        findsNothing,
      );
      expect(find.byType(PaywallScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// StoreKit 2 offline past an expiry the renewal has not reached: restore
/// answers from the device cache, which now holds nothing.
final class _OfflineStoreKit implements StoreClient {
  final StreamController<List<StorePurchase>> _updates =
      StreamController<List<StorePurchase>>.broadcast();

  /// How many times the gateway asked. Tells a restore that ran from one
  /// that joined another already in flight.
  int restores = 0;

  @override
  bool get emptyRestoreRevokes => false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<StoreProductQuery> queryProducts(Set<String> ids) async =>
      StoreProductQuery(
        products: <StoreProduct>[
          for (final String id in ids)
            StoreProduct(
              id: id,
              title: id,
              description: 'Tasuke Pro',
              price: '₸2 490',
              rawPrice: 2490,
              currencyCode: 'KZT',
            ),
        ],
        notFoundIds: const <String>[],
      );

  @override
  Future<void> buy(StoreProduct product) async {}

  @override
  Future<void> restore() async {
    restores++;
    _updates.add(const <StorePurchase>[]);
  }

  @override
  Stream<List<StorePurchase>> get purchases => _updates.stream;

  @override
  Future<void> complete(StorePurchase purchase) async {}
}

final class _MemoryEntitlements implements EntitlementStore {
  _MemoryEntitlements(this._value);

  Entitlement? _value;

  @override
  Future<Entitlement?> read() async => _value;

  @override
  Future<void> write(Entitlement value) async {
    _value = value;
  }
}

/// A store that cannot be reached: the plans loaded, then the network went.
final class _FailingStore implements PurchaseGateway {
  _FailingStore(this.plans);

  final List<SubscriptionPlan> plans;
  final StreamController<Entitlement> _entitlements =
      StreamController<Entitlement>.broadcast();

  static const PurchaseFailure _offline = PurchaseFailure(
    'The store does not know this product',
    kind: PurchaseFailureKind.productNotFound,
  );

  @override
  Future<void> initialise() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<SubscriptionPlan>> loadPlans() async => plans;

  @override
  Future<void> buy(SubscriptionPlan plan) async => throw _offline;

  @override
  Future<void> restore() async => throw _offline;

  @override
  Stream<Entitlement> get entitlements => _entitlements.stream;

  @override
  Entitlement get current => Entitlement.free;

  @override
  Future<void> dispose() async => _entitlements.close();
}

/// A store whose purchase stays open until the test closes it.
///
/// [FakePurchaseGateway] completes a purchase within the same microtask, which
/// is the one thing a double-tap guard cannot be tested against: the paywall
/// is already gone before a second tap could land.
final class _PendingStore implements PurchaseGateway {
  @override
  Future<void> initialise() async {}

  _PendingStore(this.plans);

  final List<SubscriptionPlan> plans;
  final List<String> bought = <String>[];

  final Completer<void> _sheet = Completer<void>();
  final StreamController<Entitlement> _entitlements =
      StreamController<Entitlement>.broadcast();

  Entitlement _current = Entitlement.free;

  /// Completes the purchase the user started.
  void settle() => _sheet.complete();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<SubscriptionPlan>> loadPlans() async => plans;

  @override
  Future<void> buy(SubscriptionPlan plan) async {
    bought.add(plan.id);
    await _sheet.future;
    _current = Entitlement(
      status: EntitlementStatus.proActive,
      productId: plan.id,
    );
    _entitlements.add(_current);
  }

  @override
  Future<void> restore() async {}

  @override
  Stream<Entitlement> get entitlements => _entitlements.stream;

  @override
  Entitlement get current => _current;

  @override
  Future<void> dispose() async => _entitlements.close();
}
