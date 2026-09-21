import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';

/// The plans the store actually knows about.
///
/// ⚠️ A product that comes back in `notFoundIDs` is simply absent from this
/// list. Rendering it with a blank price is worse than hiding it, and an empty
/// list is what the paywall's "store unavailable" state is for — the usual
/// cause is an unsigned Paid Applications agreement, not a bug.
///
/// `entitlementProvider` and `isProProvider` live in
/// `core/purchases/purchase_providers.dart`, next to the gateway they read.
final FutureProvider<List<SubscriptionPlan>> subscriptionPlansProvider =
    FutureProvider<List<SubscriptionPlan>>((Ref ref) async {
      final PurchaseGateway gateway = ref.watch(purchaseGatewayProvider);
      if (!await gateway.isAvailable()) return const <SubscriptionPlan>[];
      return gateway.loadPlans();
    });
