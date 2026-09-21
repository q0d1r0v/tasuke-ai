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
  Future<void> restore() async => restoreCount++;

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
}) => StorePurchase(
  productId: productId,
  status: status,
  needsCompletion: needsCompletion,
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

  Future<void> start({Entitlement? persisted}) async {
    client = FakeStoreClient();
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
