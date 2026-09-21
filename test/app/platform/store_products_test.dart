import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';

import 'native_source.dart';

/// Keeps `store/PRODUCTS.md`, `ios/Runner/Tasuke.storekit` and
/// `lib/core/purchases/product_ids.dart` telling the same story.
///
/// `ProductIds` names this test in its own doc comment. The three files are
/// edited by three different people at three different times — a Dart
/// developer, someone writing store copy, and someone clicking through App
/// Store Connect — and the only symptom of a disagreement is a paywall that
/// renders nothing on one platform, because a product the store does not
/// recognise comes back in `notFoundIDs` and is hidden rather than shown blank.
void main() {
  late String products;
  late Map<String, Object?> storekit;

  setUpAll(() {
    products = readProjectFile('store/PRODUCTS.md');
    storekit = jsonDecode(
      readProjectFile('ios/Runner/Tasuke.storekit'),
    ) as Map<String, Object?>;
  });

  group('store/PRODUCTS.md', () {
    test('lists both product ids exactly as the code spells them', () {
      for (final String id in ProductIds.all) {
        expect(
          products,
          contains(id),
          reason: '$id is missing from PRODUCTS.md',
        );
      }
    });

    test('records the Android package the manage-subscription link uses', () {
      expect(products, contains(ProductIds.androidPackage));
      // The same string is the Gradle applicationId. A rename that touches one
      // of them sends every Android subscriber to a Play page for an app that
      // does not exist.
      final String gradle = readProjectFile('android/app/build.gradle.kts');
      expect(
        gradle,
        contains('applicationId = "${ProductIds.androidPackage}"'),
      );
    });

    test('records both prices and both grace periods', () {
      expect(products, contains(r'$4.99'));
      expect(products, contains(r'$39.99'));
      expect(products.toLowerCase(), contains('grace period'));
    });
  });

  group('ios/Runner/Tasuke.storekit', () {
    late Map<String, Object?> group0;

    setUp(() {
      final List<Object?> groups =
          storekit['subscriptionGroups']! as List<Object?>;
      expect(groups, hasLength(1), reason: 'one subscription group, not two');
      group0 = groups.single! as Map<String, Object?>;
    });

    test('has one group named tasuke_pro', () {
      expect(group0['name'], 'tasuke_pro');
    });

    test('yearly is level 1 and monthly is level 2', () {
      // ⚠️ Lower number = higher tier. This ordering is what makes
      // monthly → yearly an immediate, prorated upgrade and yearly → monthly a
      // deferred downgrade. Swap them and a user who pays to upgrade is told
      // the change applies at the end of the period: they have paid and got
      // nothing, which is a refund request and a one-star review.
      final Map<String, Map<String, Object?>> byId =
          <String, Map<String, Object?>>{
            for (final Object? entry
                in group0['subscriptions']! as List<Object?>)
              (entry! as Map<String, Object?>)['productID']! as String:
                  entry as Map<String, Object?>,
          };

      expect(byId.keys.toSet(), ProductIds.all);
      expect(byId[ProductIds.yearly]!['groupNumber'], 1);
      expect(byId[ProductIds.monthly]!['groupNumber'], 2);
      expect(byId[ProductIds.yearly]!['recurringSubscriptionPeriod'], 'P1Y');
      expect(byId[ProductIds.monthly]!['recurringSubscriptionPeriod'], 'P1M');
      expect(byId[ProductIds.yearly]!['displayPrice'], '39.99');
      expect(byId[ProductIds.monthly]!['displayPrice'], '4.99');
    });

    test('neither product has an introductory offer', () {
      // The free tier is the trial. A 7-day trial on top of it gives a new user
      // two overlapping "free" stories and makes the entitlement sequence much
      // harder to reason about.
      for (final Object? entry in group0['subscriptions']! as List<Object?>) {
        final Map<String, Object?> subscription =
            entry! as Map<String, Object?>;
        expect(
          subscription['introductoryOffer'],
          isNull,
          reason: '${subscription['productID']} must ship with no intro offer',
        );
      }
    });
  });
}
