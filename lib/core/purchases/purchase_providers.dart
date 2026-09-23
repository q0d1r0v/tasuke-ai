import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/store_page_opener.dart';
import 'package:tasuke_ai/core/purchases/store_purchase_gateway.dart';

/// The store, as a seam. Overridden in tests with a scripted fake.
final Provider<StoreClient> storeClientProvider = Provider<StoreClient>(
  (Ref ref) => PluginStoreClient(),
);

/// Opens the store's subscription page. Overridden in tests with a recorder.
final Provider<StorePageOpener> storePageOpenerProvider =
    Provider<StorePageOpener>((Ref ref) => const UrlStorePageOpener());

/// Where the last-known entitlement is persisted.
final Provider<EntitlementStore> entitlementStoreProvider =
    Provider<EntitlementStore>((Ref ref) => const PrefsEntitlementStore());

/// The purchase port.
///
/// ⚠️ `initialise()` is awaited by [appBootstrapProvider], before the first
/// route resolves. StoreKit replays unfinished transactions to whoever is
/// listening the moment the app starts, and an update delivered before anything
/// subscribes is gone — which is exactly how a paying subscriber lands on the
/// free tier, in front of the quota gate that sends them back to the paywall
/// they just bought. Play replays nothing; `initialise()` asks it instead.
///
/// ⚠️ NOT started from this create function. A create fn runs on first read,
/// which may be inside a build; starting platform work from one is the house
/// rule this file shares with `notification_providers.dart`.
final Provider<PurchaseGateway> purchaseGatewayProvider =
    Provider<PurchaseGateway>((Ref ref) {
      final StorePurchaseGateway gateway = StorePurchaseGateway(
        client: ref.watch(storeClientProvider),
        store: ref.watch(entitlementStoreProvider),
      );
      ref.onDispose(() => unawaited(gateway.dispose()));
      return gateway;
    });

/// The live entitlement. Seeded with whatever the gateway already knows, so the
/// paywall never flashes "free" at a subscriber on the way to the real answer.
final StreamProvider<Entitlement> entitlementProvider =
    StreamProvider<Entitlement>((Ref ref) {
      final PurchaseGateway gateway = ref.watch(purchaseGatewayProvider);
      return gateway.entitlements;
    });

/// Whether Pro features are unlocked right now.
final Provider<bool> isProProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(entitlementProvider).value?.isPro ??
      ref.watch(purchaseGatewayProvider).current.isPro,
);
