import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

/// The fill and shadow a CTA actually painted.
BoxDecoration decorationOf(WidgetTester tester, Type button) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(button),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

void main() {
  group('PrimaryButton', () {
    testWidgets('renders its label and reports taps', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(label: 'Save Tasks', onPressed: () => taps++),
      );

      expect(find.text('Save Tasks'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      expect(taps, 1);
    });

    testWidgets('a null onPressed fades it and drops the shadow', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        const PrimaryButton(label: 'Save Tasks', onPressed: null),
      );

      final BoxDecoration decoration = decorationOf(tester, PrimaryButton);
      expect(decoration.color, TasukeColors.primaryWash);
      expect(decoration.boxShadow, isNull);
      expect(
        tester.getSemantics(find.byType(PrimaryButton)),
        isSemantics(label: 'Save Tasks', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('busy swaps in a spinner without changing width', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(label: 'Subscribe', expanded: false, onPressed: () {}),
      );
      final double idleWidth = tester.getSize(find.byType(PrimaryButton)).width;

      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(
          label: 'Subscribe',
          expanded: false,
          busy: true,
          onPressed: () {},
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(PrimaryButton)).width, idleWidth);
    });

    testWidgets('busy ignores taps — the double-purchase guard', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(label: 'Subscribe', busy: true, onPressed: () => taps++),
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      expect(taps, 0);
    });

    testWidgets('keeps its accessibility label while busy', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(label: 'Subscribe', busy: true, onPressed: () {}),
      );

      // The visible Text sits behind Opacity(0), whose semantics the framework
      // drops — the label has to survive that anyway.
      expect(
        tester.getSemantics(find.byType(PrimaryButton)),
        isSemantics(label: 'Subscribe', isButton: true),
      );
      handle.dispose();
    });

    testWidgets('is at least the design control height', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        PrimaryButton(label: 'Save', onPressed: () {}),
      );

      expect(
        tester.getSize(find.byType(PrimaryButton)).height,
        greaterThanOrEqualTo(TasukeMetrics.controlHeight),
      );
    });
  });

  group('SecondaryButton', () {
    testWidgets('is white with a hairline, no shadow, and taps', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        SecondaryButton(label: 'Not now', onPressed: () => taps++),
      );

      final BoxDecoration decoration = decorationOf(tester, SecondaryButton);
      expect(decoration.color, TasukeColors.surface);
      expect(decoration.boxShadow, isNull);
      expect(decoration.border, isNotNull);

      await tester.tap(find.byType(SecondaryButton));
      expect(taps, 1);
    });
  });

  group('DangerButton', () {
    testWidgets('filled is solid red with a white label', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        DangerButton(label: 'Stop', filled: true, onPressed: () {}),
      );

      expect(decorationOf(tester, DangerButton).color, TasukeColors.danger);
      expect(styleOf(tester, 'Stop').color, TasukeColors.onPrimary);
    });

    testWidgets('tinted is the quiet delete', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        DangerButton(label: 'Delete Task', onPressed: () {}),
      );

      expect(decorationOf(tester, DangerButton).color, TasukeColors.dangerTint);
      expect(styleOf(tester, 'Delete Task').color, TasukeColors.danger);
    });
  });

  group('TextLinkButton', () {
    testWidgets('taps, and is a real 48pt target', (WidgetTester tester) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        TextLinkButton(label: 'Skip', onPressed: () => taps++),
      );

      await tester.tap(find.byType(TextLinkButton));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(TextLinkButton)).height,
        greaterThanOrEqualTo(TasukeMetrics.minTapTarget),
      );
    });

    testWidgets('disabled announces itself as disabled', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        const TextLinkButton(label: 'Skip', onPressed: null),
      );

      await tester.tap(find.byType(TextLinkButton));
      expect(
        tester.getSemantics(find.byType(TextLinkButton)),
        isSemantics(label: 'Skip', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('TasukeSwitch', () {
    testWidgets('reports the inverted value', (WidgetTester tester) async {
      bool? reported;
      await pumpWidgetUnderTest(
        tester,
        TasukeSwitch(
          value: false,
          semanticLabel: 'Notifications',
          onChanged: (bool value) => reported = value,
        ),
      );

      await tester.tap(find.byType(TasukeSwitch));
      expect(reported, isTrue);
    });

    testWidgets('carries its toggled state and label', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        TasukeSwitch(
          value: true,
          semanticLabel: 'Notifications',
          onChanged: (bool _) {},
        ),
      );

      expect(
        tester.getSemantics(find.byType(TasukeSwitch)),
        isSemantics(label: 'Notifications', isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('busy and disabled both ignore taps', (
      WidgetTester tester,
    ) async {
      int changes = 0;
      await pumpWidgetUnderTest(
        tester,
        TasukeSwitch(
          value: false,
          busy: true,
          onChanged: (bool _) => changes++,
        ),
      );
      await tester.tap(find.byType(TasukeSwitch));
      expect(changes, 0);

      await pumpWidgetUnderTest(
        tester,
        const TasukeSwitch(value: false, onChanged: null),
      );
      await tester.tap(find.byType(TasukeSwitch));
      expect(changes, 0);
    });

    testWidgets('is 48pt tall however short the pill is', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        TasukeSwitch(value: false, onChanged: (bool _) {}),
      );

      expect(
        tester.getSize(find.byType(TasukeSwitch)).height,
        TasukeMetrics.minTapTarget,
      );
    });
  });
}
