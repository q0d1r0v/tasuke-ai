import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

import '../../app/widgets/_harness.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The Home screen: three segments over one screen, and the greeting.
void main() {
  /// Wednesday 2026-03-11, 10:00 local — midweek, so "two days out" is a
  /// weekday name and never rolls into next month.
  final DateTime testNow = DateTime(2026, 3, 11, 10);
  const LocalDate today = LocalDate(2026, 3, 11);

  late FakeTaskRepository tasks;

  setUp(() => tasks = FakeTaskRepository());
  tearDown(() => tasks.dispose());

  Task task(
    String id,
    String title, {
    LocalDate? date,
    LocalTimeOfDay? time,
    bool completed = false,
  }) => makeTask(id: id, title: title, completed: completed).copyWith(
    due: date == null ? null : TaskDue(date: date, time: time),
    // A UTC instant that round-trips back to [testNow] in the local zone,
    // whatever zone the suite happens to run in — otherwise the Completed
    // grouping lands on a different day on a machine west of Greenwich.
    completedAt: completed ? testNow.toUtc() : null,
  );

  /// Pumps Home inside a router, because the list pushes `/task/:id`.
  ///
  /// The router is also the assertion for the segments: they are a provider,
  /// not three routes, and the only way to prove that is to watch the location
  /// while they are tapped.
  Future<GoRouter> pumpHome(WidgetTester tester, {DateTime? now}) async {
    final GoRouter router = GoRouter(
      initialLocation: '/home',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: HomeScreen()),
        ),
        GoRoute(
          path: '/task/:id',
          builder: (_, GoRouterState state) =>
              Scaffold(body: Text('detail:${state.pathParameters['id']}')),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(clock: FixedClock(now ?? testNow)),
          taskRepositoryProvider.overrideWithValue(tasks),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await pumpSettled(tester);
    return router;
  }

  /// Taps one of the three segments by its label.
  ///
  /// Scoped to the control: once Upcoming is selected the header says
  /// "Upcoming" too, and a bare `find.text` then matches two widgets.
  Future<void> tapSegment(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedTabs),
        matching: find.text(label),
      ),
    );
    await pumpSettled(tester);
  }

  /// ⚠️ Unmounted at the END of the body, never in `addTearDown`.
  ///
  /// flutter_test asserts on pending timers before teardown callbacks run, so a
  /// tree taken down in teardown reports "A Timer is still pending" — a failure
  /// that looks exactly like a leak in the code under test and is not one.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('Today lists what is due today and what is already late', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[
      task(
        't1',
        'Send the build to James',
        date: today,
        time: const LocalTimeOfDay.hm(15, 0),
      ),
      task('t2', 'Renew the domain', date: today.addDays(-2)),
      task('t3', 'Book the flights', date: today.addDays(1)),
    ]);

    await pumpHome(tester);

    expect(find.text('Send the build to James'), findsOneWidget);
    expect(find.text('Renew the domain'), findsOneWidget);
    // Tomorrow's task belongs to Upcoming. Showing it here would make Today a
    // list the user can never finish.
    expect(find.text('Book the flights'), findsNothing);

    await shutdown(tester);
  });

  testWidgets(
    'the greeting follows the clock, not the machine running the test',
    (WidgetTester tester) async {
      await pumpHome(tester, now: DateTime(2026, 3, 11, 8));
      expect(find.text('Good morning,'), findsOneWidget);

      await pumpHome(tester, now: DateTime(2026, 3, 11, 14));
      expect(find.text('Good afternoon,'), findsOneWidget);

      await pumpHome(tester, now: DateTime(2026, 3, 11, 21));
      expect(find.text('Good evening,'), findsOneWidget);

      await shutdown(tester);
    },
  );

  testWidgets('switching segments swaps the list without pushing a route', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[
      task('t1', 'Send the build to James', date: today),
      task('t2', 'Book the flights', date: today.addDays(1)),
      task('t3', 'Pay the invoice', date: today, completed: true),
    ]);

    final GoRouter router = await pumpHome(tester);
    expect(find.text('Send the build to James'), findsOneWidget);

    await tapSegment(tester, 'Upcoming');
    expect(find.text('Book the flights'), findsOneWidget);
    expect(find.text('Send the build to James'), findsNothing);

    await tapSegment(tester, 'Completed');
    expect(find.text('Pay the invoice'), findsOneWidget);
    expect(find.text('Book the flights'), findsNothing);

    // ⚠️ The point of the whole exercise: three taps, still one route. Segments
    // that pushed would leave the system back button walking the user through
    // their own tab history before it ever left Home.
    expect(router.state.uri.toString(), '/home');

    await shutdown(tester);
  });

  testWidgets('Upcoming files tasks under Tomorrow, a weekday and Next Week', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[
      task('t1', 'Book the flights', date: today.addDays(1)),
      task('t2', 'Draft the release notes', date: today.addDays(2)),
      task('t3', 'Renew the certificate', date: today.addDays(8)),
    ]);

    await pumpHome(tester);
    await tapSegment(tester, 'Upcoming');

    // Scoped to the headers: a tile's own date chip carries the same words, so
    // a bare `find.text('Tomorrow')` would pass with no header at all.
    for (final String header in <String>['Tomorrow', 'Friday', 'Next Week']) {
      expect(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.text(header),
        ),
        findsOneWidget,
        reason: 'expected a "$header" section header',
      );
    }

    await shutdown(tester);
  });

  testWidgets('Completed files tasks under the day they were finished', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[
      task('t1', 'Pay the invoice', date: today, completed: true),
    ]);

    await pumpHome(tester);
    await tapSegment(tester, 'Completed');

    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('Today'),
      ),
      findsOneWidget,
    );
    expect(find.text('Pay the invoice'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('each segment has an empty state of its own', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Nothing for today'), findsOneWidget);

    await tapSegment(tester, 'Upcoming');
    expect(find.text('Nothing coming up'), findsOneWidget);

    await tapSegment(tester, 'Completed');
    expect(find.text('Nothing completed yet'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('ticking a task off writes it through the repository', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James', date: today)]);

    await pumpHome(tester);
    await tester.tap(find.byType(CheckCircle));
    await pumpSettled(tester);

    expect(tasks.all.single.completed, isTrue);
    // And it leaves Today, because Today is the list of what is still open.
    expect(find.text('Send the build to James'), findsNothing);
    expect(find.text('Nothing for today'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('tapping a task opens its detail route', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James', date: today)]);

    final GoRouter router = await pumpHome(tester);
    await tester.tap(find.byType(TaskListTile));
    await pumpSettled(tester);

    expect(router.state.uri.toString(), '/task/t1');
    expect(find.text('detail:t1'), findsOneWidget);

    await shutdown(tester);
  });
}
