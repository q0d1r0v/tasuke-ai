/// A subscription plan as the store describes it.
///
/// ⚠️ [price] is the store's own localised string and is the only thing the
/// paywall may render. Hardcoding "$4.99" shows the wrong currency to most of
/// the world and is an App Review rejection; a guard test forbids a currency
/// literal in `lib/features/subscription/`.
final class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currencyCode,
    required this.period,
  });

  final String id;
  final String title;
  final String description;

  /// Localised, store-formatted. e.g. `US$4.99`, `4,99 €`.
  final String price;

  /// The numeric price, for computing the per-month equivalent of a year.
  final double rawPrice;
  final String currencyCode;
  final SubscriptionPeriod period;
}

enum SubscriptionPeriod { monthly, yearly }

/// What the user is entitled to right now.
enum EntitlementStatus {
  /// Not yet determined — the store has not been queried.
  unknown,
  free,
  pending,
  proActive,

  /// Payment failed but the store is still retrying; keep access.
  proGrace,

  /// Was Pro, is no longer.
  expired,
}

final class Entitlement {
  const Entitlement({required this.status, this.productId, this.expiresAt});

  static const Entitlement unknown = Entitlement(
    status: EntitlementStatus.unknown,
  );
  static const Entitlement free = Entitlement(status: EntitlementStatus.free);

  final EntitlementStatus status;
  final String? productId;

  /// UTC. Null when the store did not report one.
  final DateTime? expiresAt;

  /// Pro features are unlocked for [proActive] and [proGrace].
  ///
  /// A grace-period subscriber has a failing payment method, not a cancelled
  /// subscription; cutting them off is how you turn a billing retry into a
  /// churned customer.
  bool get isPro =>
      status == EntitlementStatus.proActive ||
      status == EntitlementStatus.proGrace;

  Entitlement copyWith({
    EntitlementStatus? status,
    String? productId,
    DateTime? expiresAt,
  }) => Entitlement(
    status: status ?? this.status,
    productId: productId ?? this.productId,
    expiresAt: expiresAt ?? this.expiresAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Entitlement &&
      other.status == status &&
      other.productId == productId &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(status, productId, expiresAt);
}

/// The store port.
abstract interface class PurchaseGateway {
  /// Restores the persisted entitlement and subscribes to the store.
  ///
  /// ⚠️ Awaited by the app bootstrap, before the first route resolves.
  /// StoreKit replays every unfinished transaction to whoever is listening at
  /// launch, and an update delivered with nothing subscribed is simply gone.
  /// Play replays nothing, so this also starts a silent [restore] once the
  /// listener is attached.
  ///
  /// Its absence shipped: the implementation existed, both of its doc comments
  /// claimed the bootstrap awaited it, and nothing called it. A user could pay,
  /// be left on the free tier, watch the quota gate send them back to the
  /// paywall they had just bought — and then have Google Play refund the
  /// purchase three days later because it was never completed.
  ///
  /// Idempotent: subscribing twice would complete every purchase twice.
  Future<void> initialise();

  /// False when the device has no store, or the Paid Applications agreement is
  /// unsigned. The paywall must say so rather than spin forever.
  Future<bool> isAvailable();

  /// Returns only the products the store actually knows about. A product that
  /// comes back in `notFoundIDs` is hidden, never rendered with a blank price.
  Future<List<SubscriptionPlan>> loadPlans();

  /// Starts a purchase. The result arrives on [entitlements].
  Future<void> buy(SubscriptionPlan plan);

  /// Asks the store what this account still holds and applies the answer —
  /// granting what it holds, and revoking Pro when it holds no paid plan.
  ///
  /// Completes once the answer has been applied, so [current] is the result.
  /// Throws when the store did not answer; that says nothing about the
  /// subscription, so nothing is revoked.
  Future<void> restore();

  /// The live entitlement, updated as the purchase stream delivers.
  Stream<Entitlement> get entitlements;

  /// The last known entitlement, available synchronously.
  Entitlement get current;

  Future<void> dispose();
}
