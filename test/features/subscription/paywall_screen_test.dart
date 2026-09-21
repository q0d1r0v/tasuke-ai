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
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/features/subscription/presentation/paywall_screen.dart';

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

  late FakePurchaseGateway store;

  setUp(() {
    store = FakePurchaseGateway(plans: <SubscriptionPlan>[monthly, yearly]);
  });

  tearDown(() => unawaited(store.dispose()));

  /// Pumps the paywall the way the app reaches it: pushed on top of something.
  ///
  /// The dismiss control pops when it can, so a paywall pumped as the root
  /// route would exercise the fallback rather than the path every user takes.
  ///
  /// ⚠️ The smallest supported phone by default. Half of what this screen has
  /// to show exists for App Review, and 320×568 is where it stops fitting.
  Future<void> pumpPaywall(
    WidgetTester tester, {
    PurchaseGateway? gateway,
    DeviceFrame frame = DeviceFrame.smallNoInsets,
  }) async {
    await tester.binding.setSurfaceSize(frame.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = GoRouter(
      initialLocation: AppRoute.home.path,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoute.home.path,
          builder: (_, _) => const Scaffold(body: Center(child: Text('Home'))),
        ),
        GoRoute(
          path: AppRoute.paywall.path,
          builder: (_, _) => const PaywallScreen(),
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
        // The paywall touches exactly one port, and handing it a second fake
        // for a provider it never reads would only hide that.
        overrides: <Override>[
          purchaseGatewayProvider.overrideWithValue(gateway ?? store),
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

    unawaited(router.push(AppRoute.paywall.path));
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

      // What the free tier still includes, so "5 a day" is not a surprise
      // discovered after declining.
      expect(
        find.textContaining('Free: 5 voice captures a day'),
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

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// A store whose purchase stays open until the test closes it.
///
/// [FakePurchaseGateway] completes a purchase within the same microtask, which
/// is the one thing a double-tap guard cannot be tested against: the paywall
/// is already gone before a second tap could land.
final class _PendingStore implements PurchaseGateway {
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
