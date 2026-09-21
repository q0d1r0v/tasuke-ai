import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

void main() {
  group('TasukeScaffold', () {
    testWidgets('shows a header only when it has something to put in it', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const TasukeScaffold(child: Text('body')),
        scrollable: false,
      );
      expect(find.byType(ScreenHeader), findsNothing);

      await pumpWidgetUnderTest(
        tester,
        const TasukeScaffold(title: 'Settings', child: Text('body')),
        scrollable: false,
      );
      expect(find.byType(ScreenHeader), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('lays the bottom bar out inside the body, under the content', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        TasukeScaffold(
          title: 'Confirm Tasks',
          bottomBar: PrimaryButton(label: 'Save Tasks', onPressed: () {}),
          // ignore: sort_child_properties_last — TasukeScaffold takes its page
          // chrome after `child`, so putting `child` last would separate the
          // title from the bar it belongs with.
          child: const Text('body'),
        ),
        scrollable: false,
      );

      // ⚠️ Not in Scaffold.bottomNavigationBar: that slot is hit-tested before
      // the body and would eat taps on the bottom of the content.
      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
      expect(find.text('Save Tasks'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Save Tasks')).dy,
        greaterThan(tester.getCenter(find.text('body')).dy),
      );
    });

    testWidgets('a scrollable body scrolls; a fixed one does not', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const TasukeScaffold(child: Text('body')),
        scrollable: false,
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      await pumpWidgetUnderTest(
        tester,
        const TasukeScaffold(scrollable: false, child: Text('body')),
        scrollable: false,
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  group('ScreenHeader', () {
    testWidgets('centres the title between equal side slots', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        SizedBox(
          width: 375,
          child: ScreenHeader(title: 'Task Details', onBack: () {}),
        ),
      );

      final double titleCentre = tester.getCenter(find.text('Task Details')).dx;
      // Within a pixel of the middle of the 375pt frame, back button or not.
      expect(titleCentre, closeTo(375 / 2, 1));
    });

    testWidgets('the back affordance only exists when it can act', (
      WidgetTester tester,
    ) async {
      int backs = 0;
      await pumpWidgetUnderTest(tester, const ScreenHeader(title: 'About'));
      expect(find.byType(IconButton), findsNothing);

      await pumpWidgetUnderTest(
        tester,
        ScreenHeader(title: 'About', onBack: () => backs++),
      );
      await tester.tap(find.byType(IconButton));
      expect(backs, 1);
    });
  });

  group('TasukeCard', () {
    testWidgets('is a plain surface until it is given an onTap', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(tester, const TasukeCard(child: Text('card')));
      expect(find.byType(InkWell), findsNothing);

      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        TasukeCard(onTap: () => taps++, child: const Text('card')),
      );
      await tester.tap(find.text('card'));
      expect(taps, 1);
    });

    testWidgets('elevated: false drops the shadow', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const TasukeCard(elevated: false, child: Text('card')),
      );

      final DecoratedBox box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TasukeCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).boxShadow, isNull);
    });
  });

  group('SectionHeader', () {
    testWidgets('renders its label and an optional trailing widget', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(label: 'Tomorrow', trailing: Text('3')),
      );

      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('IconTile', () {
    testWidgets('is square at its given size and tints its glyph', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        // Aligned, so the tile is laid out against loose constraints the way
        // a Row hands them down — a tight parent would stretch any box.
        const Align(
          alignment: Alignment.centerLeft,
          child: IconTile(
            icon: Icon(Icons.mic_rounded),
            background: TasukeColors.successTint,
            foreground: TasukeColors.success,
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(IconTile)),
        const Size.square(TasukeMetrics.iconTile),
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.mic_rounded)).color, isNull);
      final IconThemeData theme = IconTheme.of(
        tester.element(find.byIcon(Icons.mic_rounded)),
      );
      expect(theme.color, TasukeColors.success);
    });
  });

  group('SettingsRow and SettingsGroup', () {
    testWidgets('a row shows title, subtitle, trailing and a chevron', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        SettingsRow(
          title: 'Language',
          subtitle: 'English',
          trailing: const Text('English'),
          onTap: () => taps++,
        ),
      );

      expect(find.text('Language'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Language'));
      expect(taps, 1);
    });

    testWidgets('a row with no onTap has no chevron to mislead with', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SettingsRow(title: 'Version', trailing: Text('v1.0.0')),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a group hairlines between rows but not after the last', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SettingsGroup(
          header: 'General',
          children: <Widget>[
            SettingsRow(title: 'Notifications'),
            SettingsRow(title: 'Language'),
            SettingsRow(title: 'About'),
          ],
        ),
      );

      expect(find.text('General'), findsOneWidget);
      // Three rows, two separators — the group fixes the last row itself so no
      // call site has to remember `isLast`.
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('a row is at least the design row height', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SettingsRow(title: 'Notifications', isLast: true),
      );

      expect(
        tester.getSize(find.byType(SettingsRow)).height,
        greaterThanOrEqualTo(TasukeMetrics.rowHeight),
      );
    });
  });

  group('TasukeTextField', () {
    testWidgets('shows its hint and reports every keystroke', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> changes = <String>[];

      await pumpWidgetUnderTest(
        tester,
        TasukeTextField(
          controller: controller,
          hint: 'What needs doing?',
          onChanged: changes.add,
        ),
      );

      expect(find.text('What needs doing?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Call the dentist');
      expect(changes, <String>['Call the dentist']);
      expect(controller.text, 'Call the dentist');
    });
  });

  group('SegmentedTabs', () {
    testWidgets('renders every label and reports the tapped index', (
      WidgetTester tester,
    ) async {
      int? selected;
      await pumpWidgetUnderTest(
        tester,
        SegmentedTabs(
          labels: const <String>['Today', 'Upcoming', 'Completed'],
          selected: 0,
          onSelected: (int index) => selected = index,
        ),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      await tester.tap(find.text('Upcoming'));
      expect(selected, 1);
    });

    testWidgets('the selected pill animates to the selected segment', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        SizedBox(
          width: 300,
          child: SegmentedTabs(
            labels: const <String>['Today', 'Upcoming', 'Completed'],
            selected: 0,
            onSelected: (int _) {},
          ),
        ),
      );
      final double start = tester
          .getTopLeft(find.byType(AnimatedPositioned))
          .dx;

      await pumpWidgetUnderTest(
        tester,
        SizedBox(
          width: 300,
          child: SegmentedTabs(
            labels: const <String>['Today', 'Upcoming', 'Completed'],
            selected: 2,
            onSelected: (int _) {},
          ),
        ),
      );
      await tester.pump(TasukeDurations.fast);

      expect(
        tester.getTopLeft(find.byType(AnimatedPositioned)).dx,
        greaterThan(start),
      );
    });

    testWidgets('marks the selected segment for a screen reader', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        SegmentedTabs(
          labels: const <String>['Today', 'Upcoming'],
          selected: 1,
          onSelected: (int _) {},
        ),
      );

      expect(
        tester.getSemantics(find.text('Upcoming')),
        isSemantics(label: 'Upcoming', isSelected: true),
      );
      handle.dispose();
    });
  });
}
