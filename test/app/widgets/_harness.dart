import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

/// Pumps one catalogue widget the way a screen would host it.
///
/// The localisations delegates are not optional decoration: half the catalogue
/// reads `context.l10n`, and a widget test that leaves them out fails inside
/// `Localizations.of` with an error that says nothing about the missing
/// delegate.
Future<void> pumpWidgetUnderTest(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,

  /// Wraps the widget in a scroll view, which is how every screen hosts one.
  /// A state or a card that is taller than the phone at 2× type scale is only
  /// an overflow if nothing scrolls.
  bool scrollable = true,
  Size surface = const Size(375, 812),
}) async {
  // A real phone, not the 800×600 default: the nav band, the gutter and the
  // segmented tabs are all laid out against a 375pt width in the design.
  tester.view.physicalSize = surface * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // Off in tests: the banner is painted into every golden and turns the
      // top-right corner of each reference image into a red stripe.
      debugShowCheckedModeBanner: false,
      theme: TasukeTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Material(
              color: TasukeColors.canvas,
              child: scrollable ? SingleChildScrollView(child: child) : child,
            ),
          );
        },
      ),
    ),
  );
}

/// Unmounts everything, so a widget holding a repeating ticker — the orb, any
/// spinner — is disposed before the test ends.
Future<void> tearDownTree(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// A saved task with fixed timestamps.
///
/// `DateTime.now()` is banned in `lib/`; a fixture that used it would make
/// every assertion about ordering depend on the minute the suite ran.
Task makeTask({
  String id = 'task-1',
  String title = 'Send the build to James',
  bool completed = false,
}) {
  final DateTime at = DateTime.utc(2026, 9, 21, 9);
  return Task(
    id: id,
    title: title,
    completed: completed,
    createdAt: at,
    updatedAt: at,
  );
}

TaskDraft makeDraft({
  String draftId = 'draft-1',
  String title = 'Check App Store',
  bool lowConfidenceDate = false,
}) => TaskDraft(
  draftId: draftId,
  title: title,
  lowConfidenceDate: lowConfidenceDate,
);

/// The style a catalogue widget put on a piece of text.
///
/// Every widget here sets one explicitly — nothing in the catalogue leans on an
/// inherited `DefaultTextStyle` — so reading the widget is enough and the test
/// does not need to reach for the render object.
TextStyle styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;
