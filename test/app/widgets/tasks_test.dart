import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

import '_harness.dart';

void main() {
  group('TaskListTile', () {
    testWidgets('shows the title and reports the inverted completion', (
      WidgetTester tester,
    ) async {
      bool? toggled;
      await pumpWidgetUnderTest(
        tester,
        TaskListTile(
          task: makeTask(),
          onToggle: (bool value) => toggled = value,
        ),
      );

      expect(find.text('Send the build to James'), findsOneWidget);
      await tester.tap(find.byType(CheckCircle));
      expect(toggled, isTrue);
    });

    testWidgets('strikes a completed title, unless told not to', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        TaskListTile(task: makeTask(completed: true), onToggle: (bool _) {}),
      );
      expect(
        styleOf(tester, 'Send the build to James').decoration,
        TextDecoration.lineThrough,
      );

      await pumpWidgetUnderTest(
        tester,
        TaskListTile(
          task: makeTask(completed: true),
          strikeWhenDone: false,
          onToggle: (bool _) {},
        ),
      );
      expect(styleOf(tester, 'Send the build to James').decoration, isNull);
    });

    testWidgets('shows the date chip only when it is given labels', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        TaskListTile(
          task: makeTask(),
          onToggle: (bool _) {},
          relativeDayLabel: 'Today',
          timeLabel: '10:00 AM',
        ),
      );
      expect(find.text('Today, 10:00 AM'), findsOneWidget);

      await pumpWidgetUnderTest(
        tester,
        TaskListTile(
          task: makeTask(),
          onToggle: (bool _) {},
          showDate: false,
          relativeDayLabel: 'Today',
        ),
      );
      expect(find.byType(DateChip), findsNothing);
    });

    testWidgets('reports a tap on the row separately from the tick', (
      WidgetTester tester,
    ) async {
      int opens = 0;
      bool toggled = false;
      await pumpWidgetUnderTest(
        tester,
        TaskListTile(
          task: makeTask(),
          onTap: () => opens++,
          onToggle: (bool _) => toggled = true,
        ),
      );

      await tester.tap(find.text('Send the build to James'));
      expect(opens, 1);
      expect(toggled, isFalse);
    });
  });

  group('CheckCircle', () {
    testWidgets('an interactive tick is padded to a 48pt target', (
      WidgetTester tester,
    ) async {
      bool? value;
      await pumpWidgetUnderTest(
        tester,
        Align(
          alignment: Alignment.centerLeft,
          child: CheckCircle(
            checked: false,
            onChanged: (bool next) => value = next,
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(CheckCircle)),
        const Size.square(TasukeMetrics.minTapTarget),
      );
      await tester.tap(find.byType(CheckCircle));
      expect(value, isTrue);
    });

    testWidgets('a decorative tick is its glyph size and is not announced', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        const Align(
          alignment: Alignment.centerLeft,
          child: CheckCircle(checked: true, onChanged: null),
        ),
      );

      expect(
        tester.getSize(find.byType(CheckCircle)),
        const Size.square(TasukeMetrics.checkCircle),
      );
      expect(
        find.descendant(
          of: find.byType(CheckCircle),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('DateChip', () {
    testWidgets('joins the labels it is given', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Align(
          alignment: Alignment.centerLeft,
          child: DateChip(dateLabel: 'Tomorrow', timeLabel: '3:00 PM'),
        ),
      );

      expect(find.text('Tomorrow, 3:00 PM'), findsOneWidget);
    });

    testWidgets('falls back to "No date" with nothing to show', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const Align(alignment: Alignment.centerLeft, child: DateChip()),
      );

      expect(find.text('No date'), findsOneWidget);
    });

    testWidgets('a tappable chip is a real target and reports taps', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        Align(
          alignment: Alignment.centerLeft,
          child: DateChip(dateLabel: 'Today', onTap: () => taps++),
        ),
      );

      expect(
        tester.getSize(find.byType(DateChip)).height,
        greaterThanOrEqualTo(TasukeMetrics.minTapTarget),
      );
      await tester.tap(find.byType(DateChip));
      expect(taps, 1);
    });
  });

  group('EditableTaskCard', () {
    testWidgets('sends every keystroke out as a new draft', (
      WidgetTester tester,
    ) async {
      TaskDraft? updated;
      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(),
          onChanged: (TaskDraft next) => updated = next,
          onDelete: () {},
          onEditDate: () {},
          dateLabelBuilder: (TaskDraft _) => 'No date',
        ),
      );

      await tester.enterText(find.byType(TextField), 'Check App Store today');
      expect(updated?.title, 'Check App Store today');
      // The draft's identity survives an edit, or Confirm loses track of which
      // card it was.
      expect(updated?.draftId, 'draft-1');
    });

    testWidgets('reports delete and date edits', (WidgetTester tester) async {
      int deletes = 0;
      int dateEdits = 0;
      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(),
          onChanged: (TaskDraft _) {},
          onDelete: () => deletes++,
          onEditDate: () => dateEdits++,
          dateLabelBuilder: (TaskDraft _) => 'Tomorrow',
        ),
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(deletes, 1);

      await tester.tap(find.byType(DateChip));
      expect(dateEdits, 1);
    });

    testWidgets('flags a low-confidence date', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(lowConfidenceDate: true),
          onChanged: (TaskDraft _) {},
          onDelete: () {},
          onEditDate: () {},
          dateLabelBuilder: (TaskDraft _) => 'Friday',
        ),
      );

      expect(find.text('Check this date'), findsOneWidget);
    });

    testWidgets('takes a new title from the parent without losing the caret', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(),
          onChanged: (TaskDraft _) {},
          onDelete: () {},
          onEditDate: () {},
          dateLabelBuilder: (TaskDraft _) => 'No date',
        ),
      );
      final TextEditingController controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);

      // Same title coming back in: the field must be left entirely alone, or
      // the caret jumps to the end on every keystroke.
      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(),
          onChanged: (TaskDraft _) {},
          onDelete: () {},
          onEditDate: () {},
          dateLabelBuilder: (TaskDraft _) => 'Tomorrow',
        ),
      );
      expect(controller.selection.baseOffset, 2);

      await pumpWidgetUnderTest(
        tester,
        EditableTaskCard(
          draft: makeDraft(title: 'Replaced by the parent'),
          onChanged: (TaskDraft _) {},
          onDelete: () {},
          onEditDate: () {},
          dateLabelBuilder: (TaskDraft _) => 'Tomorrow',
        ),
      );
      expect(find.text('Replaced by the parent'), findsOneWidget);
    });
  });

  group('DashedAddRow', () {
    testWidgets('renders its label and reports taps', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        DashedAddRow(label: 'Add another task', onTap: () => taps++),
      );

      expect(find.text('Add another task'), findsOneWidget);
      await tester.tap(find.byType(DashedAddRow));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(DashedAddRow)).height,
        greaterThanOrEqualTo(TasukeMetrics.controlHeight),
      );
    });
  });
}
