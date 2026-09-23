import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/store_purchase_gateway.dart';

/// A store that answers from a script and counts what was asked of it.
final class FakeStoreClient implements StoreClient {
  final StreamController<List<StorePurchase>> _updates =
      StreamController<List<StorePurchase>>.broadcast();

  /// Every purchase [StorePurchaseGateway] completed, in order. The assertion
  /// this whole file exists for.
  final List<StorePurchase> completed = <StorePurchase>[];
  final List<String> bought = <String>[];

  bool available = true;
  int restoreCount = 0;
  List<StoreProduct> products = <StoreProduct>[];
  List<String> notFoundIds = <String>[];

  /// The batch a restore answers with, as the store sends it: every purchase
  /// still held, or an empty list. Null is a store that cannot be reached, and
  /// `restore()` throws the way the Android plugin does on any non-OK billing
  /// response — which is also what keeps every other test here free of a
  /// restore that changes anything.
  List<StorePurchase>? restorable;

  /// StoreKit sends the answer on its own channel, which can land after
  /// `restore()` has returned. Play adds it before.
  bool answersLate = false;

  /// `restore()` returns and no answer ever arrives.
  bool silent = false;

  /// True plays Play; false plays StoreKit, whose empty answer may be a stale
  /// device cache rather than a lapse.
  @override
  bool emptyRestoreRevokes = true;

  /// Runs inside `restore()`, before the answer is sent.
  void Function()? onRestore;

  void deliver(List<StorePurchase> batch) => _updates.add(batch);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<StorePurchase>> get purchases => _updates.stream;

  @override
  Future<StoreProductQuery> queryProducts(Set<String> ids) async =>
      StoreProductQuery(
        products: products
            .where((StoreProduct product) => ids.contains(product.id))
            .toList(),
        notFoundIds: notFoundIds,
      );

  @override
  Future<void> buy(StoreProduct product) async => bought.add(product.id);

  @override
  Future<void> restore() async {
    restoreCount++;
    onRestore?.call();
    final List<StorePurchase>? answer = restorable;
    if (answer == null) throw StateError('billing unavailable');
    if (silent) return;
    if (answersLate) {
      unawaited(Future<void>(() => deliver(answer)));
    } else {
      deliver(answer);
    }
  }

  @override
  Future<void> complete(StorePurchase purchase) async =>
      completed.add(purchase);

  Future<void> close() => _updates.close();
}

final class MemoryEntitlementStore implements EntitlementStore {
  MemoryEntitlementStore([this.value]);

  Entitlement? value;
  int writes = 0;

  @override
  Future<Entitlement?> read() async => value;

  @override
  Future<void> write(Entitlement entitlement) async {
    writes++;
    value = entitlement;
  }
}

StorePurchase update(
  StorePurchaseStatus status, {
  String productId = ProductIds.monthly,
  bool needsCompletion = true,
  bool fromRestore = false,
}) => StorePurchase(
  productId: productId,
  status: status,
  needsCompletion: needsCompletion,
  fromRestore: fromRestore,
);

/// What Play's restore answers for a purchase still waiting on a cash or
/// voucher payment.
StorePurchase unpaid({String productId = ProductIds.monthly}) => update(
  StorePurchaseStatus.pending,
  productId: productId,
  fromRestore: true,
);

/// The gateway completes purchases from a stream listener, so a delivery needs
/// a turn of the event loop before its effects are observable.
Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeStoreClient client;
  late MemoryEntitlementStore store;
  late StorePurchaseGateway gateway;

  Future<void> start({
    Entitlement? persisted,
    List<StorePurchase>? restorable,
    bool emptyRestoreRevokes = true,
  }) async {
    client = FakeStoreClient()
      ..restorable = restorable
      ..emptyRestoreRevokes = emptyRestoreRevokes;
    store = MemoryEntitlementStore(persisted);
    gateway = StorePurchaseGateway(client: client, store: store);
    await gateway.initialise();
  }

  tearDown(() async {
    await gateway.dispose();
    await client.close();
  });

  group('completePurchase', () {
    test('is called for a purchase', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();

      expect(client.completed, hasLength(1));
      expect(client.completed.single.status, StorePurchaseStatus.purchased);
    });

    test('is called for a restore', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.restored)]);
      await settle();

      expect(client.completed, hasLength(1));
    });

    test('is called for an error too', () async {
      // ⚠️ The forgotten one. An uncompleted errored transaction stays in
      // Apple's queue and is re-delivered on every launch, and any retry of the
      // same product then fails as a duplicate.
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.error)]);
      await settle();

      expect(client.completed, hasLength(1));
    });

    test('is never called for a pending purchase', () async {
      // Completing a pending purchase throws on the real plugin: it is not
      // finished, and the store will send another update when it is.
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.pending)]);
      await settle();

      expect(client.completed, isEmpty);
    });

    test('is skipped when the store says it is not needed', () async {
      await start();
      client.deliver(<StorePurchase>[
        update(StorePurchaseStatus.purchased, needsCompletion: false),
      ]);
      await settle();

      expect(client.completed, isEmpty);
    });

    test('every purchase in a batch is completed', () async {
      await start();
      client.deliver(<StorePurchase>[
        update(StorePurchaseStatus.purchased),
        update(StorePurchaseStatus.restored, productId: ProductIds.yearly),
      ]);
      await settle();

      expect(client.completed, hasLength(2));
    });
  });

  group('an error never revokes', () {
    test('a subscriber stays Pro through a failed purchase', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();
      expect(gateway.current.isPro, isTrue);

      client.deliver(<StorePurchase>[update(StorePurchaseStatus.error)]);
      await settle();

      expect(
        gateway.current.isPro,
        isTrue,
        reason:
            'a store round trip that failed says nothing about the '
            'subscription this app already knows about',
      );
    });

    test('the persisted entitlement is not overwritten by an error', () async {
      await start(
        persisted: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: ProductIds.yearly,
        ),
      );

      client.deliver(<StorePurchase>[update(StorePurchaseStatus.error)]);
      await settle();

      expect(store.value?.status, EntitlementStatus.proActive);
      expect(gateway.current.isPro, isTrue);
    });
  });

  group('cancelling', () {
    test('returns to the previous state, not to free', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();

      client.deliver(<StorePurchase>[update(StorePurchaseStatus.canceled)]);
      await settle();

      expect(gateway.current.status, EntitlementStatus.proActive);
    });

    test('leaves a free user free rather than unknown', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.canceled)]);
      await settle();

      expect(gateway.current.status, EntitlementStatus.free);
    });
  });

  group('persistence', () {
    test('Pro survives a relaunch with no store round trip', () async {
      await start(
        persisted: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: ProductIds.monthly,
        ),
      );

      expect(gateway.current.isPro, isTrue);
      expect(gateway.current.productId, ProductIds.monthly);
      // Synchronously, before anything listened. A paywall that has to await
      // the store to learn the user is already subscribed flashes the upsell
      // at them on every cold start.
      expect(store.writes, 0);
    });

    test('a purchase is written through', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();

      expect(store.writes, 1);
      expect(store.value?.productId, ProductIds.monthly);
    });

    test('a pending purchase is not persisted', () async {
      await start();
      client.deliver(<StorePurchase>[update(StorePurchaseStatus.pending)]);
      await settle();

      expect(store.writes, 0);
    });
  });

  group('the store is asked at launch', () {
    const Entitlement persistedPro = Entitlement(
      status: EntitlementStatus.proActive,
      productId: ProductIds.monthly,
    );

    test('a purchase finished while the app was closed is acknowledged and '
        'unlocks Pro', () async {
      // ⚠️ Play replays nothing at launch. A slow payment that cleared
      // overnight is only seen by asking, and an unacknowledged purchase is
      // refunded three days later.
      await start(
        restorable: <StorePurchase>[update(StorePurchaseStatus.restored)],
      );
      await settle();

      expect(client.restoreCount, 1);
      expect(client.completed, hasLength(1));
      expect(gateway.current.isPro, isTrue);
      expect(store.value?.status, EntitlementStatus.proActive);
    });

    test(
      'a store that cannot be reached fails nothing and revokes nothing',
      () async {
        await start(persisted: persistedPro);
        await settle();

        expect(client.restoreCount, 1);
        expect(gateway.current.isPro, isTrue);
        expect(store.writes, 0);
      },
    );

    test('an empty answer revokes a lapsed or refunded subscription', () async {
      await start(persisted: persistedPro, restorable: <StorePurchase>[]);
      await settle();

      expect(gateway.current.status, EntitlementStatus.expired);
      expect(gateway.current.isPro, isFalse);
      expect(store.value?.status, EntitlementStatus.expired);
    });

    test('an answer that still holds the plan keeps Pro', () async {
      await start(
        persisted: persistedPro,
        restorable: <StorePurchase>[
          update(StorePurchaseStatus.restored, needsCompletion: false),
        ],
      );
      await settle();

      expect(gateway.current.status, EntitlementStatus.proActive);
    });

    test('an unpaid pending purchase grants nothing and is not '
        'acknowledged', () async {
      await start(restorable: <StorePurchase>[unpaid()]);
      await settle();

      expect(gateway.current.isPro, isFalse);
      expect(client.completed, isEmpty);
      expect(store.writes, 0);
    });

    test('an answer holding only an unpaid purchase revokes Pro', () async {
      // ⚠️ A lapsed subscriber who resubscribed with a cash payment they never
      // made. Counted as held, it keeps Pro for as long as Play lists it.
      await start(
        persisted: persistedPro,
        restorable: <StorePurchase>[unpaid()],
      );
      await settle();

      expect(gateway.current.status, EntitlementStatus.expired);
      expect(store.value?.status, EntitlementStatus.expired);
      expect(client.completed, isEmpty);
    });

    test('a pending purchase beside a paid one neither hides nor revokes '
        'it', () async {
      final List<Entitlement> seen = <Entitlement>[];
      client = FakeStoreClient();
      store = MemoryEntitlementStore(persistedPro);
      gateway = StorePurchaseGateway(client: client, store: store);
      gateway.entitlements.listen(seen.add);
      client.restorable = <StorePurchase>[
        update(StorePurchaseStatus.restored),
        unpaid(productId: ProductIds.yearly),
      ];
      await gateway.initialise();
      await settle();

      expect(gateway.current.isPro, isTrue);
      expect(seen.last.isPro, isTrue);
    });

    testWidgets('a store that never answers revokes nothing', (
      WidgetTester tester,
    ) async {
      await start(persisted: persistedPro);
      client.silent = true;
      client.restorable = <StorePurchase>[];

      // The launch restore already failed on the unreachable store; this one
      // is left waiting on an answer that never comes.
      final Future<void> restoring = gateway.restore();
      Object? failure;
      unawaited(restoring.catchError((Object error) => failure = error));
      await tester.pump(StorePurchaseGateway.restoreTimeout * 2);

      expect(failure, isA<TimeoutException>());
      expect(gateway.current.isPro, isTrue);
      expect(store.writes, 0);
    });
  });

  group('on StoreKit, whose restore reads the device cache', () {
    const Entitlement persistedPro = Entitlement(
      status: EntitlementStatus.proActive,
      productId: ProductIds.monthly,
    );

    test('an empty answer at launch keeps a subscriber Pro', () async {
      // ⚠️ Offline across a renewal, StoreKit answers empty rather than
      // throwing. Revoked here, a paying subscriber sits on the free tier for
      // as long as the phone stays offline.
      await start(
        persisted: persistedPro,
        restorable: <StorePurchase>[],
        emptyRestoreRevokes: false,
      );
      await settle();

      expect(client.restoreCount, 1);
      expect(gateway.current.status, EntitlementStatus.proActive);
      expect(store.writes, 0);
    });

    test('a purchase found at launch is still granted and completed', () async {
      await start(
        restorable: <StorePurchase>[update(StorePurchaseStatus.restored)],
        emptyRestoreRevokes: false,
      );
      await settle();

      expect(gateway.current.isPro, isTrue);
      expect(client.completed, hasLength(1));
    });

    test('a restore the user asks for still revokes on an empty answer, and '
        'does not throw', () async {
      await start(
        persisted: persistedPro,
        restorable: <StorePurchase>[],
        emptyRestoreRevokes: false,
      );
      await settle();

      // Completing normally is what lets the paywall say "No previous
      // purchase found" rather than "The store isn't available".
      await gateway.restore();

      expect(gateway.current.status, EntitlementStatus.expired);
      expect(store.value?.status, EntitlementStatus.expired);
    });

    test('a restore the user asks for while the launch one waits still '
        'revokes', () async {
      client = FakeStoreClient()
        ..restorable = <StorePurchase>[]
        ..answersLate = true
        ..emptyRestoreRevokes = false;
      store = MemoryEntitlementStore(persistedPro);
      gateway = StorePurchaseGateway(client: client, store: store);
      await gateway.initialise();

      // It joins the launch restore still waiting on its answer, so that
      // restore must now revoke on the user's behalf.
      await gateway.restore();

      expect(client.restoreCount, 1);
      expect(gateway.current.status, EntitlementStatus.expired);
    });
  });

  group('restore', () {
    test('returns only once the answer is applied, even when it lands '
        'after the call', () async {
      await start();
      client
        ..restorable = <StorePurchase>[update(StorePurchaseStatus.restored)]
        ..answersLate = true;

      await gateway.restore();

      // No settle: the screens read `current` straight after the await.
      expect(gateway.current.isPro, isTrue);
    });

    test('throws when the store cannot answer, and changes nothing', () async {
      await start(
        persisted: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: ProductIds.yearly,
        ),
      );

      await expectLater(gateway.restore(), throwsA(isA<StateError>()));
      expect(gateway.current.isPro, isTrue);
    });

    test('a purchase that lands while it waits is not revoked by the '
        'answer', () async {
      await start();
      client
        ..restorable = <StorePurchase>[]
        ..answersLate = true
        ..onRestore = () => client.deliver(<StorePurchase>[
          update(StorePurchaseStatus.purchased),
        ]);

      await gateway.restore();

      expect(gateway.current.status, EntitlementStatus.proActive);
    });

    test('a live pending update is not taken for the answer', () async {
      // Taken for the answer, it says "nothing paid" and revokes a subscriber
      // whose real answer is still on its way.
      await start(
        persisted: const Entitlement(
          status: EntitlementStatus.proActive,
          productId: ProductIds.monthly,
        ),
      );
      await settle();
      final List<EntitlementStatus> seen = <EntitlementStatus>[];
      gateway.entitlements.listen(
        (Entitlement entitlement) => seen.add(entitlement.status),
      );
      client
        ..restorable = <StorePurchase>[update(StorePurchaseStatus.restored)]
        ..answersLate = true
        ..onRestore = () => client.deliver(<StorePurchase>[
          update(StorePurchaseStatus.pending, productId: ProductIds.yearly),
        ]);

      await gateway.restore();
      await settle();

      expect(seen, isNot(contains(EntitlementStatus.expired)));
      expect(gateway.current.status, EntitlementStatus.proActive);
    });
  });

  group('plans', () {
    test('a product the store does not know is hidden, not blank', () async {
      await start();
      client.products = <StoreProduct>[
        const StoreProduct(
          id: ProductIds.monthly,
          title: 'Monthly',
          description: 'Tasuke Pro',
          price: r'US$4.99',
          rawPrice: 4.99,
          currencyCode: 'USD',
        ),
      ];
      client.notFoundIds = <String>[ProductIds.yearly];

      final List<SubscriptionPlan> plans = await gateway.loadPlans();

      expect(plans, hasLength(1));
      expect(plans.single.id, ProductIds.monthly);
      expect(plans.single.period, SubscriptionPeriod.monthly);
      expect(plans.single.price, r'US$4.99');
    });

    test('the yearly id maps to the yearly period', () async {
      await start();
      client.products = <StoreProduct>[
        const StoreProduct(
          id: ProductIds.yearly,
          title: 'Yearly',
          description: 'Tasuke Pro',
          price: r'US$39.99',
          rawPrice: 39.99,
          currencyCode: 'USD',
        ),
      ];

      final List<SubscriptionPlan> plans = await gateway.loadPlans();
      expect(plans.single.period, SubscriptionPeriod.yearly);
    });
  });

  group('lifecycle', () {
    test('an unavailable store is reported rather than spun on', () async {
      await start();
      client.available = false;
      expect(await gateway.isAvailable(), isFalse);
    });

    test('initialise twice does not subscribe twice', () async {
      // The provider starts it eagerly and the bootstrap may await it. A second
      // subscription would complete every purchase twice, and a double
      // completion is an error the store reports rather than ignores.
      await start();
      await gateway.initialise();

      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();

      expect(client.completed, hasLength(1));
    });

    test('dispose stops listening to the store', () async {
      await start();
      await gateway.dispose();

      client.deliver(<StorePurchase>[update(StorePurchaseStatus.purchased)]);
      await settle();

      expect(client.completed, isEmpty);
    });
  });
}
