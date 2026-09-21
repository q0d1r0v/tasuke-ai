import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override` from its main library — only from
// `misc.dart`. Naming it without this import is a `non_type_as_type_argument`
// error that reads like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/task_detail/presentation/task_detail_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

import '../../app/widgets/_harness.dart';
import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// Task Details: the one screen where a saved task can be changed.
void main() {
  /// Wednesday 2026-03-11, 10:00 local.
  final DateTime testNow = DateTime(2026, 3, 11, 10);
  const LocalDate today = LocalDate(2026, 3, 11);

  /// The screen's own debounce on the title field.
  const Duration debounce = Duration(milliseconds: 400);

  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeLocalNotifier notifier;

  setUp(() {
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    notifier = FakeLocalNotifier();
  });

  tearDown(() {
    tasks.dispose();
    settings.dispose();
    notifier.dispose();
  });

  Task task({
    String id = 't1',
    String title = 'Send the build to James',
    LocalDate? date,
    LocalTimeOfDay? time,
    bool completed = false,
    bool reminder = false,
  }) {
    final TaskDue? due = date == null ? null : TaskDue(date: date, time: time);
    return makeTask(id: id, title: title, completed: completed).copyWith(
      due: due,
      reminder: due == null
          ? TaskReminder.none
          : TaskReminder(enabled: reminder, notificationId: 7),
    );
  }

  /// Pushes the detail screen over a Home page.
  ///
  /// ⚠️ Pushed rather than started on, because the screen pops itself after a
  /// delete. A route with nothing underneath cannot pop, and the assertion
  /// would fail for a reason that has nothing to do with deleting a task.
  Future<GoRouter> pumpDetail(
    WidgetTester tester, {
    String taskId = 't1',
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/home',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
        ),
        GoRoute(
          path: '/task/:id',
          builder: (_, GoRouterState state) =>
              TaskDetailScreen(taskId: state.pathParameters['id'] ?? ''),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(clock: FixedClock(testNow), notifier: notifier),
          taskRepositoryProvider.overrideWithValue(tasks),
          settingsRepositoryProvider.overrideWithValue(settings),
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

    unawaited(router.push<void>('/task/$taskId'));
    await pumpSettled(tester);
    return router;
  }

  /// The switch's own semantics node, one level under the row that merges it.
  SemanticsNode switchSemantics(WidgetTester tester) {
    final SemanticsNode row = tester.getSemantics(find.byType(TasukeSwitch));
    SemanticsNode? child;
    row.visitChildren((SemanticsNode node) {
      child = node;
      return false;
    });
    return child!;
  }

  /// ⚠️ Unmounted at the END of the body, never in `addTearDown`: the title
  /// debounce and the confirmation snack bar are both timers, and flutter_test
  /// asserts on pending timers before teardown callbacks run.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('shows the title and the date, time and reminder rows', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today, time: const LocalTimeOfDay.hm(15, 0))]);

    await pumpDetail(tester);

    expect(find.text('Task Details'), findsOneWidget);
    expect(find.text('Send the build to James'), findsOneWidget);

    for (final String row in <String>['Date', 'Time', 'Reminder']) {
      expect(find.text(row), findsOneWidget);
    }

    // ⚠️ The time is formatted through `intl`, so it is asserted through
    // `intl` — a literal '3:00 PM' here would bless a hardcoded pattern.
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.text(DateFormat.jm('en').format(DateTime(2000, 1, 1, 15))),
      findsOneWidget,
    );

    await shutdown(tester);
  });

  testWidgets('a task with no date says so on both rows', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task()]);

    await pumpDetail(tester);

    expect(find.text('No date'), findsOneWidget);
    // All day is a real state, not a missing one: it is what the reminder time
    // falls back to once a date is set.
    expect(find.text('All day'), findsOneWidget);

    await shutdown(tester);
  });

  testWidgets('editing the title writes once the typing stops', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today)]);

    await pumpDetail(tester);
    await tester.enterText(find.byType(TextField), 'Send the build to Amir');

    // Still mid-window: a write per keystroke would be a database round trip
    // and a reminder sweep for every letter.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tasks.all.single.title, 'Send the build to James');

    await tester.pump(debounce);
    await pumpSettled(tester);
    expect(tasks.all.single.title, 'Send the build to Amir');

    await shutdown(tester);
  });

  testWidgets('a title emptied by hand is never persisted', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today)]);

    await pumpDetail(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(debounce);
    await pumpSettled(tester);

    // A task with no title is unreachable in every list in the app, so the
    // field clearing itself must not be able to create one.
    expect(tasks.all.single.title, 'Send the build to James');

    await shutdown(tester);
  });

  testWidgets('turning the reminder on resolves it from the due time', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today, time: const LocalTimeOfDay.hm(15, 0))]);

    await pumpDetail(tester);
    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);

    final TaskReminder reminder = tasks.all.single.reminder;
    expect(reminder.enabled, isTrue);
    expect(reminder.at, const LocalDateTime(today, LocalTimeOfDay.hm(15, 0)));
    // The id the task already had, so editing targets the same OS alarm slot
    // instead of leaving an orphan behind.
    expect(reminder.notificationId, 7);

    // And back off again, because a reminder the user cannot take back is
    // worse than one they never set.
    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);
    expect(tasks.all.single.reminder.enabled, isFalse);

    await shutdown(tester);
  });

  testWidgets('an all-day task takes its reminder time from settings', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today)]);

    await pumpDetail(tester);
    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);

    expect(
      tasks.all.single.reminder.at,
      LocalDateTime(
        today,
        LocalTimeOfDay(AppSettings.defaults.allDayReminderMinute),
      ),
    );

    await shutdown(tester);
  });

  testWidgets('the reminder switch is dead until the task has a date', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    tasks.seed(<Task>[task()]);

    await pumpDetail(tester);

    // ⚠️ There is nothing to resolve a reminder against without a due date, so
    // the switch is disabled rather than silently doing nothing.
    // ⚠️ The flag lives one node DOWN. `getSemantics` hands back the settings
    // row's merged node, which carries no enabled state at all; the switch is
    // a merge boundary of its own and keeps its flags there.
    expect(switchSemantics(tester).flagsCollection.isEnabled, Tristate.isFalse);

    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);
    expect(tasks.all.single.reminder.enabled, isFalse);

    handle.dispose();
    await shutdown(tester);
  });

  testWidgets(
    'completing and un-completing both round-trip through the store',
    (WidgetTester tester) async {
      tasks.seed(<Task>[task(date: today)]);

      await pumpDetail(tester);
      await tester.tap(find.text('Mark complete'));
      await pumpSettled(tester);

      expect(tasks.all.single.completed, isTrue);
      expect(find.text('Mark not done'), findsOneWidget);

      await tester.tap(find.text('Mark not done'));
      await pumpSettled(tester);

      expect(tasks.all.single.completed, isFalse);
      expect(find.text('Mark complete'), findsOneWidget);

      await shutdown(tester);
    },
  );

  testWidgets('a cancelled delete leaves the task where it was', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today)]);

    final GoRouter router = await pumpDetail(tester);
    await tester.tap(find.text('Delete Task'));
    await pumpSettled(tester);

    expect(find.text('Delete this task?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await pumpSettled(tester);

    expect(tasks.all, hasLength(1));
    expect(router.state.uri.toString(), '/task/t1');

    await shutdown(tester);
  });

  testWidgets('a confirmed delete removes the task and leaves the screen', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today)]);

    final GoRouter router = await pumpDetail(tester);
    await tester.tap(find.text('Delete Task'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    expect(tasks.all, isEmpty);
    // Popped, not replaced: the user came from a list and goes back to it.
    expect(router.state.uri.toString(), '/home');

    await shutdown(tester);
  });

  testWidgets('a task id that no longer exists renders the deleted state', (
    WidgetTester tester,
  ) async {
    // ⚠️ Reachable from a notification whose task was removed while the process
    // was dead. The screen must say so, not throw on a null.
    await pumpDetail(tester, taskId: 'gone');

    expect(tester.takeException(), isNull);
    expect(find.text('Task deleted'), findsOneWidget);

    final GoRouter router = await pumpDetail(tester, taskId: 'gone');
    await tester.tap(find.text('Got it'));
    await pumpSettled(tester);
    expect(router.state.uri.toString(), '/home');

    await shutdown(tester);
  });

  testWidgets(
    'an overdue task is labelled against the clock, not the calendar',
    (WidgetTester tester) async {
      tasks.seed(<Task>[task(date: today.addDays(-1))]);

      await pumpDetail(tester);
      expect(find.text('Overdue'), findsOneWidget);

      await shutdown(tester);
    },
  );

  testWidgets('a task due today is not overdue yet', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[task(date: today, time: const LocalTimeOfDay.hm(9, 0))]);

    await pumpDetail(tester);
    // 09:00 has already passed at the fixed 10:00 "now", and the task is still
    // not overdue: overdue is a question about the day, never about the hour.
    expect(find.text('Overdue'), findsNothing);

    await shutdown(tester);
  });
}
