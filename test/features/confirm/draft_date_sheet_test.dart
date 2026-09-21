import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/confirm/presentation/draft_date_sheet.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

import '../../helpers/pump_app.dart';

/// The sheet behind a Confirm card's date chip.
///
/// It edits a copy and hands it back on Done, so every test here opens it,
/// drives it, and asserts on the draft that comes out.
void main() {
  /// Wednesday 2026-03-11. "Sunday" below is the 15th of the same month.
  const LocalDate today = LocalDate(2026, 3, 11);

  late TaskDraft? returned;

  setUp(() => returned = null);

  /// Opens the sheet over a host screen and waits for it to settle.
  Future<void> openSheet(WidgetTester tester, TaskDraft draft) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TasukeTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                returned = await showDraftDateSheet(
                  context,
                  draft: draft,
                  today: today,
                );
              },
              child: const Text('open the sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open the sheet'));
    await pumpSettled(tester);
  }

  TaskDraft draftOf({
    LocalDate? date,
    LocalTimeOfDay? time,
    bool hasReminder = false,
  }) => TaskDraft(
    draftId: 'draft-1',
    title: 'Send the build to James',
    date: date,
    time: time,
    hasReminder: hasReminder,
  );

  /// The value a row shows on its right-hand side.
  String trailingOf(WidgetTester tester, String rowTitle) {
    final Finder row = find.widgetWithText(SettingsRow, rowTitle);
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .last
        .data!;
  }

  Future<void> tapDone(WidgetTester tester) async {
    await tester.tap(find.byType(PrimaryButton));
    await pumpSettled(tester);
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a draft with no date offers no date, all day and no reminder', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, draftOf());

    expect(trailingOf(tester, 'Date'), 'No date');
    expect(trailingOf(tester, 'Time'), 'All day');
    // Nothing to clear, so the link is not drawn at all.
    expect(find.text('Clear'), findsNothing);

    await shutdown(tester);
  });

  testWidgets('picking a date labels the row and rides back out on Done', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, draftOf());

    await tester.tap(find.widgetWithText(SettingsRow, 'Date'));
    await pumpSettled(tester);
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await pumpSettled(tester);

    expect(trailingOf(tester, 'Date'), 'Sunday');

    await tapDone(tester);
    expect(returned?.date, const LocalDate(2026, 3, 15));
    // A date on its own is an all-day task; picking one invents no time.
    expect(returned?.time, isNull);

    await shutdown(tester);
  });

  testWidgets('picking a time implies today when the draft had no date', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, draftOf());

    await tester.tap(find.widgetWithText(SettingsRow, 'Time'));
    await pumpSettled(tester);
    // The dial cannot be aimed at a minute in a widget test; the picker's own
    // text-entry mode can.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await pumpSettled(tester);
    await tester.enterText(find.byType(TextField).first, '11');
    await tester.enterText(find.byType(TextField).last, '45');
    await tester.tap(find.text('OK'));
    await pumpSettled(tester);

    // ⚠️ U+202F, not a plain space: `DateFormat.jm` separates the meridiem
    // with a narrow no-break space, and a literal ' AM' here never matches.
    expect(trailingOf(tester, 'Time'), '11:45\u202fAM');
    // ⚠️ A time with no date is meaningless — nothing would ever fire — so
    // picking one has to adopt today rather than leave the draft half-set.
    expect(trailingOf(tester, 'Date'), 'Today');

    await tapDone(tester);
    expect(returned?.time, const LocalTimeOfDay.hm(11, 45));
    expect(returned?.date, today);

    await shutdown(tester);
  });

  testWidgets('a dated draft with no time reads as all day', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, draftOf(date: const LocalDate(2026, 3, 12)));

    expect(trailingOf(tester, 'Date'), 'Tomorrow');
    expect(trailingOf(tester, 'Time'), 'All day');

    await shutdown(tester);
  });

  testWidgets('Clear drops the date, the time and the reminder together', (
    WidgetTester tester,
  ) async {
    await openSheet(
      tester,
      draftOf(
        date: const LocalDate(2026, 3, 12),
        time: const LocalTimeOfDay.hm(15, 0),
        hasReminder: true,
      ),
    );

    await tester.tap(find.text('Clear'));
    await pumpSettled(tester);

    expect(trailingOf(tester, 'Date'), 'No date');
    expect(trailingOf(tester, 'Time'), 'All day');

    await tapDone(tester);
    expect(returned?.date, isNull);
    expect(returned?.time, isNull);
    // ⚠️ The reminder goes with it. A reminder left enabled on a dateless
    // draft is a notification with no instant to fire at.
    expect(returned?.hasReminder, isFalse);

    await shutdown(tester);
  });

  group('the reminder switch', () {
    testWidgets('is dead while the draft has no date', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await openSheet(tester, draftOf());

      expect(
        tester.getSemantics(find.byType(TasukeSwitch)),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );

      await tester.tap(find.byType(TasukeSwitch));
      await pumpSettled(tester);
      await tapDone(tester);

      expect(returned?.hasReminder, isFalse);

      handle.dispose();
      await shutdown(tester);
    });

    testWidgets('turns on once the draft has a date to fire against', (
      WidgetTester tester,
    ) async {
      await openSheet(tester, draftOf(date: const LocalDate(2026, 3, 12)));

      await tester.tap(find.byType(TasukeSwitch));
      await pumpSettled(tester);
      await tapDone(tester);

      expect(returned?.hasReminder, isTrue);
      expect(returned?.date, const LocalDate(2026, 3, 12));

      await shutdown(tester);
    });
  });
}
