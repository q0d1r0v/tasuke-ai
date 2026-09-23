import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    as android;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    as android;
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
    this.fromRestore = false,
    this.handle,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// The plugin's `pendingCompletePurchase`.
  final bool needsCompletion;

  /// Sent in answer to a restore. Only a `pending` one needs it: Play's answer
  /// holds an unpaid purchase as `pending`, and so is a live update.
  final bool fromRestore;

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

  /// Whether an empty restore answer proves the account holds nothing, even
  /// offline. Only then may the silent launch restore revoke Pro; a restore
  /// the user asks for revokes either way.
  bool get emptyRestoreRevokes;

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

  /// How long a restore waits for each half of the store's answer.
  static const Duration restoreTimeout = Duration(seconds: 10);

  /// The restore waiting for its answer batch; completes with whether the
  /// answer holds a paid plan.
  Completer<bool>? _answer;
  Future<void>? _restoring;

  /// Whether the restore in flight may revoke. A restore the user asks for
  /// raises it on a silent one it joins, so its empty answer still revokes.
  bool _mayRevoke = false;

  @override
  Entitlement get current => _current;

  @override
  Stream<Entitlement> get entitlements => _entitlements.stream;

  /// Restores the persisted entitlement and subscribes to the store.
  ///
  /// ⚠️ Subscribe **before** the first screen is built. StoreKit replays every
  /// unfinished transaction as soon as anything listens, and an update
  /// delivered before there is a listener is simply lost — which is how a
  /// subscriber ends up on the free tier after an app restart.
  ///
  /// ⚠️ Play replays nothing. A purchase that finished while the app was not
  /// running — a slow payment clearing, a resubscribe from the Play Store, a
  /// process killed mid-sheet — is only seen by asking, so this also starts a
  /// silent [restore]. Unasked, it is never acknowledged and Play refunds it
  /// three days later.
  ///
  /// The persisted value is read first and on purpose: this app is offline-first
  /// and the store round-trip may never succeed. Pro survives a relaunch on a
  /// plane.
  ///
  /// Idempotent: the bootstrap awaits it once, before the first route
  /// resolves, and subscribing twice would complete every purchase twice.
  @override
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

    // ⚠️ After `listen`: the answer arrives on the stream, and a broadcast
    // update with no listener is dropped. Detached, because billing may take
    // longer than the bootstrap's five seconds, or never connect.
    unawaited(_restoreOnLaunch());
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
  Future<void> restore() async {
    // The answer arrives on the stream, so the stream must be listened to.
    await initialise();
    await _restoreOnce(revoke: true);
  }

  Future<void> _restoreOnLaunch() async {
    try {
      // ⚠️ Only a store whose empty answer is proof may revoke unasked.
      // StoreKit's restore reads the device's cache and never syncs, so a
      // subscriber offline across a renewal gets an empty answer rather than
      // a throw, and would drop to the free tier. There, a lapse is found when
      // the user taps Restore.
      await _restoreOnce(revoke: _client.emptyRestoreRevokes);
    } on Object catch (error) {
      // Offline, no Play services, a signed-out store: none of it says
      // anything about the subscription, and the persisted value stands.
      Log.w('purchase restore on launch failed — $error');
    }
  }

  /// One at a time: a second restore would race the first for its answer.
  Future<void> _restoreOnce({required bool revoke}) {
    _mayRevoke |= revoke;
    return _restoring ??= _reconcile().whenComplete(() {
      _restoring = null;
      _mayRevoke = false;
    });
  }

  /// Asks the store what this account holds, and revokes Pro when the answer
  /// holds no paid plan and [_mayRevoke] allows it.
  ///
  /// ⚠️ Decided from the answer batch, never from `restore()` returning. Play
  /// adds the batch to the stream before its future completes; StoreKit sends
  /// it on a separate channel that can land after. Both send an empty batch
  /// when nothing is held.
  ///
  /// ⚠️ A throw or a timeout is a store that did not answer, and revokes
  /// nothing. An unpaid (`pending`) purchase in the answer does not keep Pro:
  /// when it is paid, the live update or the next launch grants it again.
  Future<void> _reconcile() async {
    final Completer<bool> answer = Completer<bool>();
    _answer = answer;
    final Entitlement asked = _current;
    try {
      await _client.restore().timeout(restoreTimeout);
      final bool holdsPaidPlan = await answer.future.timeout(restoreTimeout);
      // `identical`: a purchase that landed while this waited is newer than
      // the answer, and the answer must not revoke it.
      if (_mayRevoke &&
          !holdsPaidPlan &&
          _current.isPro &&
          identical(_current, asked)) {
        _set(
          Entitlement(
            status: EntitlementStatus.expired,
            productId: _current.productId,
          ),
        );
      }
    } finally {
      if (identical(_answer, answer)) _answer = null;
    }
  }

  Future<void> _onPurchases(List<StorePurchase> batch) async {
    // Every update is applied before the first await, so a restore waiting on
    // this batch reads the entitlement it produced, not the one before it.
    for (final StorePurchase purchase in batch) {
      _apply(purchase);
    }
    _answerRestore(batch);
    for (final StorePurchase purchase in batch) {
      await _completeIfNeeded(purchase);
    }
  }

  /// Hands a waiting restore its answer: whether it holds a paid plan.
  ///
  /// A restore answers with every purchase still held — `restored`, or
  /// `pending` while unpaid — or with an empty batch. A live update is never
  /// empty and never `restored`.
  ///
  /// ⚠️ A live `pending` is not the answer. Taken for one, it says "nothing
  /// paid" and revokes a subscriber whose real answer is still on its way.
  void _answerRestore(List<StorePurchase> batch) {
    final Completer<bool>? answer = _answer;
    if (answer == null || answer.isCompleted) return;
    final bool isAnswer = batch.every(
      (StorePurchase purchase) =>
          purchase.status == StorePurchaseStatus.restored ||
          purchase.fromRestore,
    );
    if (!isAnswer) return;
    answer.complete(
      batch.any(
        (StorePurchase purchase) =>
            purchase.status == StorePurchaseStatus.restored,
      ),
    );
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
        // "waiting for approval" forever if the approval never comes. Nor does
        // it hide a plan already paid for, held in the same restore.
        _emit(
          _current.isPro
              ? _current
              : const Entitlement(status: EntitlementStatus.pending),
        );
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

  /// Play only. Play's answer comes from the Play Store's own copy of the
  /// account, which offline still holds the subscription, and a billing
  /// error throws. StoreKit 2's `restorePurchases` walks
  /// `Transaction.currentEntitlements` from the device cache and never syncs:
  /// offline past an expiry the renewal has not reached, it answers empty.
  @override
  bool get emptyRestoreRevokes =>
      defaultTargetPlatform == TargetPlatform.android;

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
          status: _isUnpaidOnPlay(details)
              ? StorePurchaseStatus.pending
              : switch (details.status) {
                  iap.PurchaseStatus.pending => StorePurchaseStatus.pending,
                  iap.PurchaseStatus.purchased => StorePurchaseStatus.purchased,
                  iap.PurchaseStatus.error => StorePurchaseStatus.error,
                  iap.PurchaseStatus.restored => StorePurchaseStatus.restored,
                  iap.PurchaseStatus.canceled => StorePurchaseStatus.canceled,
                },
          needsCompletion: details.pendingCompletePurchase,
          fromRestore: details.status == iap.PurchaseStatus.restored,
          handle: details,
        ),
      )
      .toList();

  /// ⚠️ Play's restore labels EVERY purchase it holds `restored`, including one
  /// still waiting on a cash or voucher payment. Taken at its word, that grants
  /// Pro for a purchase nobody has paid for, and tries to acknowledge it.
  static bool _isUnpaidOnPlay(iap.PurchaseDetails details) =>
      details is android.GooglePlayPurchaseDetails &&
      details.billingClientPurchase.purchaseState ==
          android.PurchaseStateWrapper.pending;
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
