import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

/// One store's pair of prices.
typedef Prices = ({String monthly, String yearly});

/// The plan cards at the paywall's own width, on the phones and type sizes
/// where they used to break.
///
/// ⚠️ No overflow is thrown by any of the failures below, so the overflow-only
/// paywall test stayed green through all of them: the price column shared the
/// row by flex, capped at 40% of it, and a UZS price was drawn at half size on
/// a 320pt phone and at a quarter at 2× type; "Monthly" broke as "Monthl / y"
/// and "1 month" as "1 / mont / h". These assert what was drawn instead.
void main() {
  const List<Prices> stores = <Prices>[
    (monthly: r'$4.99', yearly: r'$39.99'),
    (monthly: 'UZS 62 900,00', yearly: 'UZS 499 000,00'),
  ];

  const List<({double width, double scale})> phones =
      <({double width, double scale})>[
        (width: 320, scale: 1),
        (width: 320, scale: 2),
        (width: 407, scale: 1),
      ];

  /// [text] on one line at [scale], unconstrained: what a full-size, unbroken
  /// rendering measures.
  Size natural(String text, TextStyle style, double scale) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
      maxLines: 1,
    )..layout();
    final Size size = painter.size;
    painter.dispose();
    return size;
  }

  /// The rectangle [finder]'s text is PAINTED in: `getRect` goes through
  /// every transform above it, so a scaled-down line measures small here.
  Rect painted(WidgetTester tester, Finder finder) => tester.getRect(finder);

  Future<void> pumpPlans(
    WidgetTester tester, {
    required Prices prices,
    required double width,
    required double scale,
  }) async {
    await pumpWidgetUnderTest(
      tester,
      // The paywall's list pads by the gutter on each side.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PlanCard(
              title: 'Monthly',
              price: prices.monthly,
              period: '1 month',
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: TasukeSpacing.cardGap),
            PlanCard(
              title: 'Yearly',
              price: prices.yearly,
              period: '1 year',
              badge: 'Save 34%',
              footnote: 'UZS 41583.33 per month, billed yearly',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
      ),
      textScale: scale,
      surface: Size(width, 1600),
    );
  }

  for (final Prices prices in stores) {
    for (final ({double width, double scale}) phone in phones) {
      final String where =
          '${prices.yearly} at ${phone.width.toInt()}pt, ${phone.scale}x';

      testWidgets('$where: every label is whole, on one line, at full size', (
        WidgetTester tester,
      ) async {
        await pumpPlans(
          tester,
          prices: prices,
          width: phone.width,
          scale: phone.scale,
        );
        expect(tester.takeException(), isNull);

        final Map<String, TextStyle> labels = <String, TextStyle>{
          'Monthly': TasukeTypography.titleSm,
          'Yearly': TasukeTypography.titleSm,
          '1 month': TasukeTypography.bodySm,
          '1 year': TasukeTypography.bodySm,
          'Save 34%': TasukeTypography.badge,
        };
        for (final MapEntry<String, TextStyle> label in labels.entries) {
          final Size full = natural(label.key, label.value, phone.scale);
          final Rect drawn = painted(tester, find.text(label.key));
          // One line tall and as wide as the whole word: neither broken
          // ("Monthl / y") nor shrunk to squeeze in.
          expect(
            drawn.height,
            moreOrLessEquals(full.height, epsilon: 0.5),
            reason: '"${label.key}" is not one full-size line',
          );
          expect(
            drawn.width,
            moreOrLessEquals(full.width, epsilon: 0.5),
            reason: '"${label.key}" was scaled or clipped',
          );
        }

        await tearDownTree(tester);
      });

      testWidgets('$where: the price stays readable', (
        WidgetTester tester,
      ) async {
        await pumpPlans(
          tester,
          prices: prices,
          width: phone.width,
          scale: phone.scale,
        );
        expect(tester.takeException(), isNull);

        for (final String price in <String>[prices.monthly, prices.yearly]) {
          final Rect drawn = painted(tester, find.text(price));
          final Size unscaled = natural(price, TasukeTypography.price, 1);
          // Never smaller than the design size at 1×, whatever the phone.
          expect(
            drawn.height,
            greaterThanOrEqualTo(unscaled.height - 0.5),
            reason: '$price is drawn smaller than at 1×',
          );
          if (phone.scale == 1) {
            // At normal type there is always room for the design size.
            expect(
              drawn.width,
              moreOrLessEquals(unscaled.width, epsilon: 0.5),
              reason: '$price was shrunk at 1×',
            );
          }

          // Inside its own card, never clipped by it.
          final Rect card = tester.getRect(
            find.ancestor(
              of: find.text(price),
              matching: find.byType(PlanCard),
            ),
          );
          expect(drawn.left, greaterThanOrEqualTo(card.left));
          expect(drawn.right, lessThanOrEqualTo(card.right));
        }

        await tearDownTree(tester);
      });
    }
  }

  testWidgets(r'a short price sits beside the title, as designed', (
    WidgetTester tester,
  ) async {
    for (final double width in <double>[320, 407]) {
      await pumpPlans(tester, prices: stores.first, width: width, scale: 1);

      final Rect title = painted(tester, find.text('Yearly'));
      final Rect price = painted(tester, find.text(r'$39.99'));
      expect(price.left, greaterThan(title.right), reason: '${width}pt');
      expect(price.top, lessThan(title.bottom), reason: '${width}pt');
    }

    await tearDownTree(tester);
  });

  testWidgets('a price too wide to sit beside the title goes under it', (
    WidgetTester tester,
  ) async {
    await pumpPlans(tester, prices: stores.last, width: 320, scale: 1);

    final Rect title = painted(tester, find.text('Yearly'));
    final Rect price = painted(tester, find.text('UZS 499 000,00'));
    final Rect period = painted(tester, find.text('1 year'));
    expect(price.top, greaterThanOrEqualTo(title.bottom));
    expect(period.top, greaterThanOrEqualTo(price.bottom));
    expect(price.left, moreOrLessEquals(title.left, epsilon: 0.5));

    await tearDownTree(tester);
  });

  testWidgets('large type stacks the card whatever the price', (
    WidgetTester tester,
  ) async {
    // Past 1.3× the title column beside even "$4.99" is too narrow for
    // "Monthly" and its badge.
    await pumpPlans(tester, prices: stores.first, width: 407, scale: 1.5);

    final Rect title = painted(tester, find.text('Monthly'));
    final Rect price = painted(tester, find.text(r'$4.99'));
    expect(price.top, greaterThanOrEqualTo(title.bottom));

    await tearDownTree(tester);
  });
}
