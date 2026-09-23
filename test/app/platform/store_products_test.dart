import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/l10n/app_localizations_en.dart';
import 'package:tasuke_ai/core/purchases/product_ids.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';

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

    test("gives Apple's grace period a value App Store Connect offers", () {
      // ⚠️ Apple's billing grace period is one app-wide setting of 3, 16 or 28
      // days. A per-product number cannot be entered.
      final String apple = products.substring(
        products.indexOf('## Apple'),
        products.indexOf('## Google'),
      );
      final String line = apple
          .split('\n- ')
          .firstWhere((String item) => item.contains('grace period'));
      final List<String> days = RegExp(r'(\d+) days')
          .allMatches(line)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(days, isNotEmpty, reason: line);
      expect(<String>{'3', '16', '28'}.containsAll(days), isTrue, reason: line);
    });
  });

  group('free tier wording', () {
    // ⚠️ The in-app strings are ICU plurals and follow the constant on their
    // own. These store texts spell the number out, so they do not. A listing
    // that promises more than the app gives is misleading metadata to both
    // stores.
    const Map<int, Map<String, String>> phrases = <int, Map<String, String>>{
      1: <String, String>{
        'store/store-listing.txt': 'One capture every day, spoken or typed',
        'store/REVIEW_NOTES.md': '1 capture per day, spoken or typed',
        'store/PRODUCTS.md': '1 capture a day, spoken or typed',
        'assets/legal/terms_en.md': 'one capture per calendar day',
        'store/terms.html': 'one capture per calendar day',
      },
    };

    test('every store text states freeDailyCaptures', () {
      const int free = ExtractionDefaults.freeDailyCaptures;
      expect(
        phrases.keys,
        contains(free),
        reason:
            'freeDailyCaptures is $free: add the phrase each store text must '
            'use, then update those texts',
      );
      phrases[free]!.forEach((String path, String phrase) {
        final String text = readProjectFile(path)
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(text, contains(phrase), reason: path);
      });
    });
  });

  group('store/REVIEW_NOTES.md', () {
    late String notes;

    setUpAll(() {
      notes = readProjectFile('store/REVIEW_NOTES.md')
          .replaceAll(RegExp(r'\s+'), ' ');
    });

    test('quotes the paywall line exactly as the app shows it', () {
      // App Review is told to look for this line after the day's capture.
      const int free = ExtractionDefaults.freeDailyCaptures;
      final String line = AppLocalizationsEn().paywallQuotaHeader(free, free);
      expect(notes, contains('"$line"'));
    });

    test('names the Settings row that opens the paywall by its title', () {
      // ⚠️ "Settings → Tasuke Pro" named the row's value for a subscriber; a
      // reviewer on a free account sees "Subscription", with "Free Plan".
      final AppLocalizationsEn l10n = AppLocalizationsEn();
      expect(notes, contains('Settings → ${l10n.settingsSubscription}'));
      expect(notes, isNot(contains('Settings → ${l10n.paywallTitle}')));
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

    test('describes Pro as the paywall does, and promises nothing more', () {
      // ⚠️ "Unlimited voice capture and advanced on-device extraction" said
      // only voice was limited, when typed tasks count too, and promised an
      // extraction every user already gets. Local StoreKit testing hands it
      // to the app as each product's description, and it is the obvious draft
      // for App Store Connect's own description fields.
      final String benefit = AppLocalizationsEn().paywallBenefitUnlimited;
      final List<Object?> subscriptions =
          group0['subscriptions']! as List<Object?>;
      final List<String> descriptions = <String>[
        for (final Object? owner in <Object?>[group0, ...subscriptions])
          for (final Object? entry
              in (owner! as Map<String, Object?>)['localizations']!
                  as List<Object?>)
            (entry! as Map<String, Object?>)['description']! as String,
      ];

      expect(descriptions, hasLength(3));
      for (final String description in descriptions) {
        expect(description, startsWith(benefit), reason: description);
        for (final String untrue in <String>['voice', 'advanced', 'extract']) {
          expect(
            description.toLowerCase(),
            isNot(contains(untrue)),
            reason: description,
          );
        }
        // App Store Connect's limit for a subscription's description.
        expect(description.length, lessThanOrEqualTo(55), reason: description);
      }
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
