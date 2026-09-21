import 'dart:async';
import 'dart:convert';

import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';

/// A product as the store describes it, with the plugin's own object carried
/// opaquely in [handle] so the purchase call can hand it straight back.
final class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    this.handle,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final double rawPrice;
  final String currencyCode;
  final Object? handle;
}

/// What the store answered, including what it did not recognise.
final class StoreProductQuery {
  const StoreProductQuery({required this.products, required this.notFoundIds});

  final List<StoreProduct> products;
  final List<String> notFoundIds;
}

enum StorePurchaseStatus { pending, purchased, error, restored, canceled }

/// One purchase update.
final class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    required this.needsCompletion,
    this.handle,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// The plugin's `pendingCompletePurchase`.
  final bool needsCompletion;

  final Object? handle;
}

/// Everything [StorePurchaseGateway] needs from `in_app_purchase`.
///
/// The seam exists for one reason above all others: `completePurchase` is the
/// call this app cannot afford to miss, and the only way to *prove* it is always
/// made is a test that counts the calls. A MethodChannel cannot be counted under
/// `flutter test`.
abstract interface class StoreClient {
  Future<bool> isAvailable();

  Future<StoreProductQuery> queryProducts(Set<String> ids);

  Future<void> buy(StoreProduct product);

  Future<void> restore();

  Stream<List<StorePurchase>> get purchases;

  Future<void> complete(StorePurchase purchase);
}

/// Where the last-known entitlement lives between launches.
abstract interface class EntitlementStore {
  Future<Entitlement?> read();

  Future<void> write(Entitlement value);
}

/// The store port.
final class StorePurchaseGateway implements PurchaseGateway {
  StorePurchaseGateway({required this._client, required this._store});

  final StoreClient _client;
  final EntitlementStore _store;

  final StreamController<Entitlement> _entitlements =
      StreamController<Entitlement>.broadcast();

  StreamSubscription<List<StorePurchase>>? _updates;
  Future<void>? _started;
  Entitlement _current = Entitlement.unknown;

  @override
  Entitlement get current => _current;

  @override
  Stream<Entitlement> get entitlements => _entitlements.stream;

  /// Restores the persisted entitlement and subscribes to the store.
  ///
  /// ⚠️ Subscribe **before** the first screen is built. The store replays every
  /// purchase that was never completed as soon as anything listens, and an
  /// update delivered before there is a listener is simply lost — which is how a
  /// subscriber ends up on the free tier after an app restart.
  ///
  /// The persisted value is read first and on purpose: this app is offline-first
  /// and the store round-trip may never succeed. Pro survives a relaunch on a
  /// plane.
  ///
  /// Idempotent: the provider starts it eagerly and the bootstrap may await it,
  /// and subscribing twice would complete every purchase twice.
  Future<void> initialise() => _started ??= _initialise();

  Future<void> _initialise() async {
    final Entitlement? persisted = await _store.read();
    if (persisted != null) {
      _current = persisted;
      _emit(persisted);
    } else {
      _current = Entitlement.free;
    }

    _updates = _client.purchases.listen(
      (List<StorePurchase> batch) => unawaited(_onPurchases(batch)),
      onError: (Object error, StackTrace stack) =>
          Log.e('purchase stream error', error, stack),
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _client.isAvailable();
    } on Object catch (error, stack) {
      Log.e('store availability check failed', error, stack);
      return false;
    }
  }

  @override
  Future<List<SubscriptionPlan>> loadPlans() async {
    final StoreProductQuery query = await _client.queryProducts(ProductIds.all);
    if (query.notFoundIds.isNotEmpty) {
      // ⚠️ Hidden, never rendered with a blank price. A product id that is not
      // configured — or whose Paid Applications agreement lapsed — comes back
      // here, and a paywall row showing a title with no price is both a broken
      // purchase and an App Review rejection.
      Log.w('store did not recognise ${query.notFoundIds.join(', ')}');
    }
    return query.products
        .map(
          (StoreProduct product) => SubscriptionPlan(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            rawPrice: product.rawPrice,
            currencyCode: product.currencyCode,
            period: _periodOf(product.id),
          ),
        )
        .toList();
  }

  @override
  Future<void> buy(SubscriptionPlan plan) async {
    final StoreProductQuery query = await _client.queryProducts(<String>{
      plan.id,
    });
    final List<StoreProduct> matches = query.products
        .where((StoreProduct product) => product.id == plan.id)
        .toList();
    if (matches.isEmpty) {
      throw const PurchaseFailure(
        'The store does not know this product',
        kind: PurchaseFailureKind.productNotFound,
      );
    }
    // ⚠️ `buyNonConsumable`, not `buyConsumable`. An auto-renewing subscription
    // is a non-consumable as far as both stores are concerned; buying it as a
    // consumable consumes the entitlement on Android and the user loses Pro at
    // the next launch.
    await _client.buy(matches.first);
  }

  @override
  Future<void> restore() => _client.restore();

  Future<void> _onPurchases(List<StorePurchase> batch) async {
    for (final StorePurchase purchase in batch) {
      _apply(purchase);
      await _completeIfNeeded(purchase);
    }
  }

  /// ⚠️ The single most expensive line in this file to get wrong.
  ///
  /// Every `purchased`, `restored` and `error` update with
  /// `pendingCompletePurchase` must be completed. Miss it and Android
  /// auto-refunds the purchase after three days, while iOS keeps the transaction
  /// in its unfinished queue and re-delivers it on *every* app start — and any
  /// further attempt to buy the same product fails as a duplicate. Both symptoms
  /// appear days later, to real customers, and neither shows up in testing.
  ///
  /// It is inside a try/finally-shaped guard because a failed completion must
  /// not stop the next purchase in the batch from being completed.
  Future<void> _completeIfNeeded(StorePurchase purchase) async {
    // Completing a *pending* purchase throws: it is not finished yet, and the
    // store will send another update when it is.
    if (!purchase.needsCompletion) return;
    if (purchase.status == StorePurchaseStatus.pending) return;
    try {
      await _client.complete(purchase);
    } on Object catch (error, stack) {
      Log.e('completePurchase failed for ${purchase.productId}', error, stack);
    }
  }

  void _apply(StorePurchase purchase) {
    switch (purchase.status) {
      case StorePurchaseStatus.purchased:
      case StorePurchaseStatus.restored:
        _set(
          Entitlement(
            status: EntitlementStatus.proActive,
            productId: purchase.productId,
          ),
        );
      case StorePurchaseStatus.pending:
        // Deliberately not persisted: a pending purchase is an Ask-to-Buy or a
        // slow payment method, and writing it would leave the app showing
        // "waiting for approval" forever if the approval never comes.
        _emit(const Entitlement(status: EntitlementStatus.pending));
      case StorePurchaseStatus.error:
        // ⚠️ An error NEVER revokes. This app is offline-first: a store round
        // trip that fails says nothing about whether the user is subscribed, and
        // dropping an existing subscriber to the free tier because their
        // network blinked is the worst bug this file could have.
        _emit(_knownOrFree());
      case StorePurchaseStatus.canceled:
        // Back to whatever was true before the user opened the sheet — not to
        // `free`. Cancelling a purchase flow is not cancelling a subscription.
        _emit(_knownOrFree());
    }
  }

  Entitlement _knownOrFree() =>
      _current.status == EntitlementStatus.unknown ||
          _current.status == EntitlementStatus.pending
      ? Entitlement.free
      : _current;

  void _set(Entitlement value) {
    _current = value;
    unawaited(_store.write(value));
    _emit(value);
  }

  void _emit(Entitlement value) {
    if (!_entitlements.isClosed) _entitlements.add(value);
  }

  static SubscriptionPeriod _periodOf(String productId) =>
      productId == ProductIds.yearly
      ? SubscriptionPeriod.yearly
      : SubscriptionPeriod.monthly;

  @override
  Future<void> dispose() async {
    await _updates?.cancel();
    _updates = null;
    await _entitlements.close();
  }
}

/// The one importer of `package:in_app_purchase`.
final class PluginStoreClient implements StoreClient {
  PluginStoreClient({iap.InAppPurchase? store})
    : _store = store ?? iap.InAppPurchase.instance;

  final iap.InAppPurchase _store;

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Stream<List<StorePurchase>> get purchases =>
      _store.purchaseStream.map(_mapBatch);

  @override
  Future<StoreProductQuery> queryProducts(Set<String> ids) async {
    final iap.ProductDetailsResponse response = await _store
        .queryProductDetails(ids);
    if (response.error != null) {
      Log.w('queryProductDetails: ${response.error}');
    }
    return StoreProductQuery(
      products: response.productDetails
          .map(
            (iap.ProductDetails details) => StoreProduct(
              id: details.id,
              title: details.title,
              description: details.description,
              price: details.price,
              rawPrice: details.rawPrice,
              currencyCode: details.currencyCode,
              handle: details,
            ),
          )
          .toList(),
      notFoundIds: response.notFoundIDs,
    );
  }

  @override
  Future<void> buy(StoreProduct product) async {
    final Object? handle = product.handle;
    if (handle is! iap.ProductDetails) {
      throw const PurchaseFailure(
        'Product came from somewhere other than the store',
        kind: PurchaseFailureKind.productNotFound,
      );
    }
    await _store.buyNonConsumable(
      purchaseParam: iap.PurchaseParam(productDetails: handle),
    );
  }

  @override
  Future<void> restore() => _store.restorePurchases();

  @override
  Future<void> complete(StorePurchase purchase) async {
    final Object? handle = purchase.handle;
    if (handle is! iap.PurchaseDetails) return;
    await _store.completePurchase(handle);
  }

  static List<StorePurchase> _mapBatch(List<iap.PurchaseDetails> batch) => batch
      .map(
        (iap.PurchaseDetails details) => StorePurchase(
          productId: details.productID,
          status: switch (details.status) {
            iap.PurchaseStatus.pending => StorePurchaseStatus.pending,
            iap.PurchaseStatus.purchased => StorePurchaseStatus.purchased,
            iap.PurchaseStatus.error => StorePurchaseStatus.error,
            iap.PurchaseStatus.restored => StorePurchaseStatus.restored,
            iap.PurchaseStatus.canceled => StorePurchaseStatus.canceled,
          },
          needsCompletion: details.pendingCompletePurchase,
          handle: details,
        ),
      )
      .toList();
}

/// The last-known entitlement, in SharedPreferences.
///
/// One key, JSON-encoded, because the shape will grow (a grace-period end date
/// is the obvious next field) and three parallel keys drift out of step the
/// first time a write is interrupted between them.
final class PrefsEntitlementStore implements EntitlementStore {
  const PrefsEntitlementStore();

  static const String key = 'tasuke.entitlement';

  @override
  Future<Entitlement?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final Map<String, Object?> json = jsonDecode(raw) as Map<String, Object?>;
      final String? status = json['status'] as String?;
      final int? expiresMs = json['expiresAt'] as int?;
      return Entitlement(
        status: EntitlementStatus.values.firstWhere(
          (EntitlementStatus value) => value.name == status,
          orElse: () => EntitlementStatus.free,
        ),
        productId: json['productId'] as String?,
        expiresAt: expiresMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresMs, isUtc: true),
      );
    } on Object catch (error) {
      // A value this app wrote in an older shape. Treat it as absent rather than
      // crashing on launch; the store will re-deliver the truth anyway.
      Log.w('could not read the persisted entitlement — $error');
      return null;
    }
  }

  @override
  Future<void> write(Entitlement value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(<String, Object?>{
        'status': value.status.name,
        'productId': value.productId,
        'expiresAt': value.expiresAt?.toUtc().millisecondsSinceEpoch,
      }),
    );
  }
}
