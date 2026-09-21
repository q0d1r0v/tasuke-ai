/// The subscription product identifiers.
///
/// ⚠️ These strings must match what is configured in App Store Connect and in
/// the Play Console **exactly**. `store/PRODUCTS.md` records the same values,
/// and `test/app/platform/store_products_test.dart` asserts the two agree — so
/// a typo in a console id surfaces as a red test rather than as an empty
/// paywall in production.
abstract final class ProductIds {
  static const String monthly = 'tasuke_pro_monthly';
  static const String yearly = 'tasuke_pro_yearly';

  static const Set<String> all = <String>{monthly, yearly};

  /// Where to send an existing subscriber who taps "Manage subscription".
  static const String appleManageUrl =
      'https://apps.apple.com/account/subscriptions';

  static const String androidPackage = 'uz.digitalgroup.tasuke';

  static String androidManageUrl(String productId) =>
      'https://play.google.com/store/account/subscriptions'
      '?sku=$productId&package=$androidPackage';
}
