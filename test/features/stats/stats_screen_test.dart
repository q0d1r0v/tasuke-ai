import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/features/stats/presentation/stats_providers.dart';
import 'package:tasuke_ai/features/stats/presentation/stats_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// Stats: three counters, a streak sentence and a seven-day bar row.
void main() {
  final DateTime testNow = DateTime(2026, 3, 11, 10);

  late FakeTaskRepository tasks;

  setUp(() => tasks = FakeTaskRepository());
  tearDown(() => tasks.dispose());

  /// Pumps the screen over a fixed [TaskStats].
  ///
  /// The stats provider is overridden rather than fed through the store,
  /// because a five-day streak and an uneven week are states the fake store
  /// cannot be talked into and are exactly the ones the layout has to survive.
  Future<void> pumpStats(WidgetTester tester, {TaskStats? stats}) async {
    // ⚠️ A fresh tree per pump, not an updated one. A `ProviderScope` that is
    // rebuilt in place keeps the container it already made, so a second
    // `overrideWith` inside one test is silently ignored and the screen goes on
    // showing the first set of numbers. Unmounting first is what makes the
    // three streak arms below three real states instead of one.
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpScreen(
      tester,
      const Scaffold(body: StatsScreen()),
      overrides: <Override>[
        ...defaultOverrides(clock: FixedClock(testNow)),
        taskRepositoryProvider.overrideWithValue(tasks),
        if (stats != null)
          taskStatsProvider.overrideWith(
            (Ref ref) => Stream<TaskStats>.value(stats),
          ),
      ],
    );
  }

  /// One column of the week row, scoped to the card that holds them so a
  /// rounded box elsewhere on the screen can never be counted as a day.
  Finder columns() => find.descendant(
    of: find.byType(TasukeCard).last,
    matching: find.byType(FractionallySizedBox),
  );

  /// The filled part of each column — what the user actually reads as a bar.
  Finder bars() =>
      find.descendant(of: columns(), matching: find.byType(DecoratedBox));

  List<double> barHeights(WidgetTester tester) => <double>[
    for (int i = 0; i < bars().evaluate().length; i++)
      tester.getSize(bars().at(i)).height,
  ];

  /// ⚠️ Unmounted at the END of the body, never in `addTearDown`: flutter_test
  /// asserts on pending timers before teardown callbacks run.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('the three counters carry the numbers the store handed over', (
    WidgetTester tester,
  ) async {
    await pumpStats(
      tester,
      stats: const TaskStats(
        pending: 4,
        completedTotal: 12,
        completedThisWeek: 3,
        streakDays: 2,
        completionsByDay: <int>[0, 0, 0, 0, 0, 0, 0],
      ),
    );

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('the streak sentence has an arm for none, one and many', (
    WidgetTester tester,
  ) async {
    TaskStats withStreak(int days) => TaskStats(
      pending: 2,
      completedTotal: 6,
      completedThisWeek: 1,
      streakDays: days,
      completionsByDay: const <int>[0, 0, 0, 0, 0, 0, 0],
    );

    await pumpStats(tester, stats: withStreak(0));
    expect(find.text('No streak yet'), findsOneWidget);

    // Singular, not "1 days streak" — the plural arms are the whole reason
    // this string is an ICU message rather than an interpolation.
    await pumpStats(tester, stats: withStreak(1));
    expect(find.text('1 day streak'), findsOneWidget);

    await pumpStats(tester, stats: withStreak(5));
    expect(find.text('5 day streak'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('the week row draws one bar per day, scaled to the busiest', (
    WidgetTester tester,
  ) async {
    await pumpStats(
      tester,
      stats: const TaskStats(
        pending: 1,
        completedTotal: 6,
        completedThisWeek: 6,
        streakDays: 2,
        completionsByDay: <int>[0, 1, 2, 0, 3, 0, 0],
      ),
    );

    expect(find.text('Last 7 days'), findsOneWidget);
    expect(bars(), findsNWidgets(7));

    final List<double> heights = barHeights(tester);
    // The busiest day fills its column, and each quieter day is shorter than
    // the one that beat it — the row is a comparison or it is decoration.
    expect(heights[4], tester.getSize(columns().at(4)).height);
    expect(heights[1], lessThan(heights[2]));
    expect(heights[2], lessThan(heights[4]));
    // A day with nothing done still shows a stub, so the week reads as seven
    // days rather than as four.
    expect(heights[0], greaterThan(0));
    expect(heights[0], lessThan(heights[1]));

    // Each column is labelled with its own count.
    expect(
      find.descendant(
        of: find.byType(TasukeCard).last,
        matching: find.text('0'),
      ),
      findsNWidgets(4),
    );

    await shutdown(tester);
  });

  testWidgets(
    'a brand-new install shows the empty state, not a wall of zeros',
    (WidgetTester tester) async {
      // Straight through the repository rather than an overridden snapshot: an
      // install with nothing in it is the state every first launch is in.
      await pumpStats(tester);

      expect(find.text('No stats yet'), findsOneWidget);
      expect(
        find.text('Complete a task and your progress shows up here.'),
        findsOneWidget,
      );
      // No counters, no streak card, no bars — the empty state is the whole
      // screen.
      expect(find.byType(TasukeCard), findsNothing);

      await shutdown(tester);
    },
  );

  testWidgets('a week with nothing completed scales without dividing by zero', (
    WidgetTester tester,
  ) async {
    // ⚠️ Not the empty state: one pending task is enough to render the body,
    // and then the bar row has to scale seven zeros against a peak of zero. A
    // NaN height factor fails in layout, so the absence of an exception here is
    // half the assertion.
    await pumpStats(
      tester,
      stats: const TaskStats(
        pending: 1,
        completedTotal: 0,
        completedThisWeek: 0,
        streakDays: 0,
        completionsByDay: <int>[0, 0, 0, 0, 0, 0, 0],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(bars(), findsNWidgets(7));

    final List<double> heights = barHeights(tester);
    expect(heights.first, greaterThan(0));
    expect(heights, everyElement(heights.first));

    await shutdown(tester);
  });
}
