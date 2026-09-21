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
import 'package:tasuke_ai/features/search/presentation/search_providers.dart';
import 'package:tasuke_ai/features/search/presentation/search_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

import '../../app/widgets/_harness.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// Search: a prompt, a debounce and a list.
void main() {
  final DateTime testNow = DateTime(2026, 3, 11, 10);
  const LocalDate today = LocalDate(2026, 3, 11);

  /// The screen's own debounce. Typed out here rather than imported because a
  /// test that reads the constant it is checking cannot fail when the constant
  /// changes — and the whole point is that the window stays short.
  const Duration debounce = Duration(milliseconds: 220);

  late FakeTaskRepository tasks;

  setUp(() => tasks = FakeTaskRepository());
  tearDown(() => tasks.dispose());

  Task task(String id, String title) =>
      makeTask(id: id, title: title).copyWith(due: const TaskDue(date: today));

  Future<GoRouter> pumpSearch(WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/search',
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (_, _) => const Scaffold(body: SearchScreen()),
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
          ...defaultOverrides(clock: FixedClock(testNow)),
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

  /// The query the list is actually being built from.
  String queryInFlight(WidgetTester tester) {
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SearchScreen)),
      listen: false,
    );
    return container.read(searchQueryProvider);
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  /// ⚠️ Unmounted at the END of the body, never in `addTearDown`: the screen
  /// cancels its debounce in `dispose`, and flutter_test asserts on pending
  /// timers before teardown callbacks run.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('an empty query prompts instead of listing everything', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James')]);

    await pumpSearch(tester);

    expect(find.text('Search your tasks'), findsOneWidget);
    expect(find.text('Type a word from a task title.'), findsOneWidget);
    expect(find.byType(TaskListTile), findsNothing);

    await shutdown(tester);
  });

  testWidgets('typing does not run a query on every keystroke', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[
      task('t1', 'Send the build to James'),
      task('t2', 'Buy milk'),
    ]);

    await pumpSearch(tester);

    // Three keystrokes inside one debounce window. Each one restarts the timer,
    // so a LIKE query over every task never runs for the prefixes.
    for (final String typed in <String>['b', 'bu', 'buil']) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(queryInFlight(tester), isEmpty);
    }
    expect(find.text('Search your tasks'), findsOneWidget);

    // Then stop typing, and the window elapses.
    await tester.enterText(find.byType(TextField), 'build');
    await tester.pump(debounce + const Duration(milliseconds: 50));
    await pumpSettled(tester);

    expect(queryInFlight(tester), 'build');
    expect(find.text('Send the build to James'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);

    await shutdown(tester);
  });

  testWidgets('a query that matches nothing is echoed back to the user', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James')]);

    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'kayak');
    await tester.pump(debounce + const Duration(milliseconds: 50));
    await pumpSettled(tester);

    expect(find.text('No tasks match "kayak"'), findsOneWidget);
    expect(find.byType(TaskListTile), findsNothing);

    await shutdown(tester);
  });

  testWidgets('the clear button empties the field and the query together', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James')]);

    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'build');
    await tester.pump(debounce + const Duration(milliseconds: 50));
    await pumpSettled(tester);
    expect(find.byType(TaskListTile), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await pumpSettled(tester);

    // Both halves: a field that still reads "build" over the prompt state is
    // the bug this button is for.
    expect(fieldText(tester), isEmpty);
    expect(queryInFlight(tester), isEmpty);
    expect(find.text('Search your tasks'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('tapping a result opens its detail route', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task('t1', 'Send the build to James')]);

    final GoRouter router = await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'build');
    await tester.pump(debounce + const Duration(milliseconds: 50));
    await pumpSettled(tester);

    await tester.tap(find.byType(TaskListTile));
    await pumpSettled(tester);

    expect(router.state.uri.toString(), '/task/t1');
    expect(find.text('detail:t1'), findsOneWidget);

    await shutdown(tester);
  });
}
