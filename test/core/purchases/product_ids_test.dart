import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';

void main() {
  group('the manage-subscription page', () {
    test('Apple has one page for every subscription', () {
      expect(
        ProductIds.manageUri(apple: true, productId: ProductIds.monthly),
        Uri.parse('https://apps.apple.com/account/subscriptions'),
      );
    });

    test('Play opens the plan the subscriber holds', () {
      final Uri page = ProductIds.manageUri(
        apple: false,
        productId: ProductIds.yearly,
      );

      expect(page.host, 'play.google.com');
      expect(page.queryParameters, <String, String>{
        'sku': ProductIds.yearly,
        'package': ProductIds.androidPackage,
      });
    });

    test("Play without a known plan opens the app's subscriptions", () {
      final Uri page = ProductIds.manageUri(apple: false);

      expect(page.path, '/store/account/subscriptions');
      expect(page.queryParameters, <String, String>{
        'package': ProductIds.androidPackage,
      });
    });
  });
}
