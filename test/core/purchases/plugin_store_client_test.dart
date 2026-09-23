import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/core/purchases/store_purchase_gateway.dart';

/// The plugin's purchase stream, and nothing else.
final class _PlayStream extends Fake implements iap.InAppPurchase {
  final StreamController<List<iap.PurchaseDetails>> updates =
      StreamController<List<iap.PurchaseDetails>>.broadcast();

  @override
  Stream<List<iap.PurchaseDetails>> get purchaseStream => updates.stream;
}

/// One Play purchase as `restorePurchases()` hands it over: whatever its real
/// state, the plugin overwrites the status with `restored`.
GooglePlayPurchaseDetails _restoredFromPlay(PurchaseStateWrapper state) =>
    _fromPlay(state)..status = iap.PurchaseStatus.restored;

/// One Play purchase as a live update hands it over.
GooglePlayPurchaseDetails _fromPlay(PurchaseStateWrapper state) =>
    GooglePlayPurchaseDetails.fromPurchase(
      PurchaseWrapper(
        orderId: 'GPA.0001',
        packageName: ProductIds.androidPackage,
        purchaseTime: 0,
        purchaseToken: 'token',
        signature: 'signature',
        products: const <String>[ProductIds.monthly],
        isAutoRenewing: true,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: state,
      ),
    ).single;

void main() {
  late _PlayStream play;
  late PluginStoreClient client;

  setUp(() {
    play = _PlayStream();
    client = PluginStoreClient(store: play);
  });

  tearDown(() => play.updates.close());

  Future<StorePurchase> mapped(iap.PurchaseDetails details) async {
    final Future<List<StorePurchase>> next = client.purchases.first;
    play.updates.add(<iap.PurchaseDetails>[details]);
    return (await next).single;
  }

  test(
    'an unpaid Play purchase is pending, whatever restore labelled it',
    () async {
      // ⚠️ Taken at its word, this is Pro for a cash or voucher payment that
      // was never made — and an acknowledgement of a purchase not yet paid.
      final StorePurchase purchase = await mapped(
        _restoredFromPlay(PurchaseStateWrapper.pending),
      );

      expect(purchase.status, StorePurchaseStatus.pending);
      expect(purchase.fromRestore, isTrue);
    },
  );

  test('a paid Play purchase stays restored', () async {
    final StorePurchase purchase = await mapped(
      _restoredFromPlay(PurchaseStateWrapper.purchased),
    );

    expect(purchase.status, StorePurchaseStatus.restored);
    expect(purchase.fromRestore, isTrue);
    expect(purchase.needsCompletion, isTrue);
  });

  test('a live pending update is not marked as a restore answer', () async {
    // Only the answer may revoke Pro; a live pending update must not pass
    // for one.
    final StorePurchase purchase = await mapped(
      _fromPlay(PurchaseStateWrapper.pending),
    );

    expect(purchase.status, StorePurchaseStatus.pending);
    expect(purchase.fromRestore, isFalse);
  });

  group('an empty restore answer', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is proof of a lapse on Play', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(client.emptyRestoreRevokes, isTrue);
    });

    test('is not proof on StoreKit, which answers from the device cache', () {
      // ⚠️ Offline across a renewal, StoreKit 2 answers empty. Trusted, it
      // drops a paying subscriber to the free tier at launch.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(client.emptyRestoreRevokes, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(client.emptyRestoreRevokes, isFalse);
    });
  });
}
