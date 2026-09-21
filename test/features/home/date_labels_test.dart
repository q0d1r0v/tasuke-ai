import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

import '../../app/widgets/_harness.dart';

/// `DateLabels` is the one place a date becomes a string a user reads.
///
/// It needs a `BuildContext` — every label is either an ARB lookup or an `intl`
/// format against the active locale — so these are `testWidgets`, but nothing
/// here is a widget test: the tree exists only to own the localisations.
void main() {
  /// Wednesday 2026-03-11. Midweek and far from any month or year boundary, so
  /// a failure is never ambiguous between a bug and an off-by-one in the
  /// fixture.
  const LocalDate today = LocalDate(2026, 3, 11);

  /// The tag `DateLabels` passes to `intl`, and the one the expectations below
  /// format against. Reading it from the tree rather than typing 'en' keeps the
  /// assertions honest the day a second locale ships.
  late String locale;

  /// Pumps a tree whose only job is to own the localisations, and hands back a
  /// context under them.
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    BuildContext? captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    final BuildContext context = captured!;
    locale = Localizations.localeOf(context).toLanguageTag();
    return context;
  }

  group('day', () {
    testWidgets('the three days either side of today are named, not dated', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      expect(DateLabels.day(context, today, today), 'Today');
      expect(DateLabels.day(context, today.addDays(1), today), 'Tomorrow');
      expect(DateLabels.day(context, today.addDays(-1), today), 'Yesterday');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the rest of the coming week is the weekday name', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      // Two days out is Friday; six days out is the last day still inside the
      // week window.
      expect(DateLabels.day(context, today.addDays(2), today), 'Friday');
      expect(DateLabels.day(context, today.addDays(6), today), 'Tuesday');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a date inside this year drops the year, beyond it keeps it', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      // ⚠️ Formatted through `intl`, never against a pattern typed here: the
      // field order is locale data the app does not own. What the app *does*
      // own is which format it reaches for, so the year is what is asserted.
      const LocalDate thisYear = LocalDate(2026, 9, 26);
      const LocalDate nextYear = LocalDate(2027, 9, 26);

      expect(
        DateLabels.day(context, thisYear, today),
        DateFormat.MMMd(locale).format(thisYear.toDateTimeLocal()),
      );
      expect(DateLabels.day(context, thisYear, today), isNot(contains('2026')));

      expect(
        DateLabels.day(context, nextYear, today),
        DateFormat.yMMMd(locale).format(nextYear.toDateTimeLocal()),
      );
      expect(DateLabels.day(context, nextYear, today), contains('2027'));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the past gets a date, never a weekday', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      // Last Monday is two days back. A weekday name there would read as the
      // *coming* Monday, which is the whole reason the window is one-sided.
      final LocalDate lastMonday = today.addDays(-2);
      expect(
        DateLabels.day(context, lastMonday, today),
        DateFormat.MMMd(locale).format(lastMonday.toDateTimeLocal()),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('time', () {
    testWidgets('is whatever the locale writes, not a 12-hour pattern', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      // ⚠️ Asserted against `DateFormat.jm`, not against the literal
      // '3:00 PM'. Most of Europe writes 15:00 with no meridiem, and a test
      // that pins the English string is a test that blesses a hardcoded
      // 'h:mm a' the day a second locale ships.
      for (final LocalTimeOfDay at in <LocalTimeOfDay>[
        const LocalTimeOfDay.hm(15, 0),
        const LocalTimeOfDay.hm(0, 0),
        const LocalTimeOfDay.hm(12, 5),
      ]) {
        expect(
          DateLabels.time(context, at),
          DateFormat.jm(locale)
              .format(DateTime(2000, 1, 1, at.hour, at.minute)),
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('taskMeta', () {
    testWidgets('a task with no due date is Someday, not an empty line', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      expect(DateLabels.taskMeta(context, makeTask(), today), 'Someday');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an all-day task says so where the time would go', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      final Task allDay = makeTask().copyWith(due: const TaskDue(date: today));
      expect(DateLabels.taskMeta(context, allDay, today), 'Today, All day');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a timed task pairs the day with the formatted time', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      final Task timed = makeTask().copyWith(
        due: TaskDue(
          date: today.addDays(1),
          time: const LocalTimeOfDay.hm(10, 0),
        ),
      );
      final String time = DateFormat.jm(locale)
          .format(DateTime(2000, 1, 1, 10));
      expect(DateLabels.taskMeta(context, timed, today), 'Tomorrow, $time');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('groupHeader', () {
    /// A group carries a label and a date; the tasks under it never reach the
    /// header, so an empty list is the honest fixture.
    TaskGroup group(TaskGroupLabel label, LocalDate date) =>
        TaskGroup(label: label, date: date, tasks: const <Task>[]);

    testWidgets('every label arm has a header of its own', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.today, today),
          today,
        ),
        'Today',
      );
      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.tomorrow, today.addDays(1)),
          today,
        ),
        'Tomorrow',
      );
      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.weekday, today.addDays(2)),
          today,
        ),
        'Friday',
      );
      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.nextWeek, today.addDays(9)),
          today,
        ),
        'Next Week',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('later and completedOn fall back to the day label', (
      WidgetTester tester,
    ) async {
      final BuildContext context = await pumpContext(tester);

      final LocalDate far = today.addDays(40);
      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.later, far),
          today,
        ),
        DateFormat.MMMd(locale).format(far.toDateTimeLocal()),
      );

      // Completed lists group by the day the task was finished, so their dates
      // are in the past and the relative names are the ones that matter.
      expect(
        DateLabels.groupHeader(
          context,
          group(TaskGroupLabel.completedOn, today.addDays(-1)),
          today,
        ),
        'Yesterday',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('greeting', () {
    testWidgets('turns over at noon and at six', (WidgetTester tester) async {
      final BuildContext context = await pumpContext(tester);

      expect(
        DateLabels.greeting(context, DateTime(2026, 3, 11, 8)),
        'Good morning,',
      );
      // The boundaries belong to the later greeting: 12:00 is afternoon and
      // 18:00 is evening, not the last minute of the one before.
      expect(
        DateLabels.greeting(context, DateTime(2026, 3, 11, 12)),
        'Good afternoon,',
      );
      expect(
        DateLabels.greeting(context, DateTime(2026, 3, 11, 17, 59)),
        'Good afternoon,',
      );
      expect(
        DateLabels.greeting(context, DateTime(2026, 3, 11, 18)),
        'Good evening,',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
