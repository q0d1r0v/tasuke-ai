import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/notifications/local_notifier.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/reminders/data/local_reminder_scheduler.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/settings/domain/app_settings.dart';
import 'package:tasuke_ai/features/settings/presentation/settings_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// Settings.
///
/// Three of these rows are store obligations rather than conveniences —
/// Restore Purchases, the two legal documents and the in-app deletion path —
/// so "the row exists and goes somewhere" is a real assertion here.
void main() {
  /// Monday 2026-09-21, 10:30 local.
  final DateTime testNow = DateTime(2026, 9, 21, 10, 30);
  final Clock clock = FixedClock(testNow);
  final LocalDate today = LocalDate.today(testNow);

  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late FakeLocalNotifier notifier;
  late FakePurchaseGateway store;

  setUp(() {
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    notifier = FakeLocalNotifier();
    store = FakePurchaseGateway();
  });

  tearDown(() {
    tasks.dispose();
    settings.dispose();
    usage.dispose();
    notifier.dispose();
    unawaited(store.dispose());
  });

  /// Pumps Settings inside the chrome the shell gives it, with every
  /// destination stubbed so a tap can be checked without dragging six other
  /// screens into this file.
  ///
  /// ⚠️ 1200pt tall on purpose. `ListView` builds lazily, so on a real phone
  /// the rows below the fold are simply absent from the tree and an inventory
  /// test would be asserting the viewport height rather than the design.
  Future<GoRouter> pumpSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    GoRoute stub(AppRoute route, String label) => GoRoute(
      path: route.path,
      builder: (_, _) => Scaffold(body: Center(child: Text(label))),
    );

    final GoRouter router = GoRouter(
      initialLocation: AppRoute.settings.path,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoute.settings.path,
          builder: (_, _) => const Scaffold(
            backgroundColor: TasukeColors.canvas,
            body: SettingsScreen(),
          ),
        ),
        stub(AppRoute.language, 'Language screen'),
        stub(AppRoute.paywall, 'Paywall screen'),
        stub(AppRoute.usage, 'Usage screen'),
        stub(AppRoute.about, 'About screen'),
        stub(AppRoute.help, 'Help screen'),
        stub(AppRoute.privacy, 'Privacy screen'),
        stub(AppRoute.terms, 'Terms screen'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            clock: clock,
            notifier: notifier,
            purchases: store,
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          taskRepositoryProvider.overrideWithValue(tasks),
          usageRepositoryProvider.overrideWithValue(usage),
          // A real version string, so the About row cannot pass on the
          // hardcoded fallback.
          packageInfoProvider.overrideWith(
            (Ref ref) async => PackageInfo(
              appName: 'Tasuke AI',
              packageName: 'com.tasuke.ai',
              version: '1.4.2',
              buildNumber: '142',
            ),
          ),
        ],
        child: MaterialApp.router(
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

  /// A task the scheduler would want the OS to hold: tomorrow at 09:00.
  Task reminderTask() => Task(
    id: 'task-1',
    title: 'Send the build to James',
    createdAt: testNow.toUtc(),
    updatedAt: testNow.toUtc(),
    due: TaskDue(date: today.addDays(1), time: const LocalTimeOfDay.hm(9, 0)),
    reminder: TaskReminder(
      enabled: true,
      at: LocalDateTime(today.addDays(1), const LocalTimeOfDay.hm(9, 0)),
      notificationId: 7,
    ),
  );

  testWidgets('every row the design sheet lists is on the screen', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    for (final String row in <String>[
      'Notifications',
      'Language',
      'Subscription',
      'Usage',
      'Restore Purchases',
      'Privacy Policy',
      'Terms of Service',
      'Help & Support',
      'About',
      'Delete all data',
    ]) {
      expect(find.text(row), findsOneWidget, reason: '$row is missing');
    }

    // The version is read from the platform, not typed into the ARB.
    expect(find.text('v1.4.2'), findsOneWidget);
    expect(find.byType(TasukeSwitch), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a free account reads its plan and what is left of today', (
    WidgetTester tester,
  ) async {
    await usage.recordCapture(today, taskCount: 2);
    await usage.recordCapture(today, taskCount: 1);

    await pumpSettings(tester);

    expect(find.text('Free Plan'), findsOneWidget);
    expect(find.text('2 / 5 today'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a subscriber reads Tasuke Pro and an uncounted quota', (
    WidgetTester tester,
  ) async {
    store.emit(
      const Entitlement(
        status: EntitlementStatus.proActive,
        productId: 'pro.yearly',
      ),
    );

    await pumpSettings(tester);

    expect(find.text('Tasuke Pro'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    // Counting captures at a subscriber is the kind of detail that reads as a
    // broken purchase.
    expect(find.textContaining('/ 5 today'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning Notifications off empties the OS queue immediately', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[reminderTask()]);
    // The alarm the OS is already holding for that task.
    notifier.scheduled.add(
      ScheduledReminder(
        id: 7,
        title: 'Send the build to James',
        body: 'Tap to open this task.',
        atLocal: LocalDateTime(today.addDays(1), const LocalTimeOfDay.hm(9, 0)),
        payload: encodeReminderPayload('task-1'),
      ),
    );

    await pumpSettings(tester);
    expect(tester.widget<TasukeSwitch>(find.byType(TasukeSwitch)).value, true);

    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);

    expect((await settings.read()).notificationsEnabled, isFalse);
    // ⚠️ A kill switch, not a filter. A user who revokes consent stops being
    // interrupted now, not at whatever the next write happens to be.
    expect(notifier.cancelled, contains(7));
    expect(notifier.scheduled, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning it back on re-arms the reminders that survived', (
    WidgetTester tester,
  ) async {
    await settings.write(
      AppSettings.defaults.copyWith(notificationsEnabled: false),
    );
    tasks.seed(<Task>[reminderTask()]);

    await pumpSettings(tester);
    expect(tester.widget<TasukeSwitch>(find.byType(TasukeSwitch)).value, false);

    await tester.tap(find.byType(TasukeSwitch));
    await pumpSettled(tester);

    expect((await settings.read()).notificationsEnabled, isTrue);
    expect(notifier.scheduled.map((ScheduledReminder r) => r.id), <int>[
      7,
    ], reason: 'the same sweep that clears the queue is what refills it');
    expect(notifier.scheduled.single.payload, contains('task-1'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Restore Purchases reaches the store from Settings too', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Restore Purchases'));
    await pumpSettled(tester);

    expect(store.restoreCount, 1);
    // Nothing was found, and saying so beats a silent tap.
    expect(find.text('No previous purchase found'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Delete all data asks before it erases anything', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[reminderTask()]);
    await pumpSettings(tester);

    await tester.tap(find.text('Delete all data'));
    await pumpSettled(tester);

    expect(find.text('Delete everything?'), findsOneWidget);
    expect(
      find.text(
        'Every task, setting and reminder on this device will be erased. '
        "This can't be undone.",
      ),
      findsOneWidget,
    );
    // Nothing has happened yet.
    expect(tasks.all, hasLength(1));

    await tester.tap(find.text('Cancel'));
    await pumpSettled(tester);

    expect(tasks.all, hasLength(1));
    expect(notifier.cancelledAll, isFalse);
    expect(find.text('All data deleted'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirming it clears the alarms, the tasks and the settings', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[reminderTask()]);
    await settings.write(
      AppSettings.defaults.copyWith(notificationsEnabled: false),
    );
    await usage.recordCapture(today, taskCount: 3);

    await pumpSettings(tester);

    await tester.tap(find.text('Delete all data'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    // ⚠️ The alarms go first: a task row deleted while its alarm is still
    // scheduled leaves a notification that opens a task that no longer exists.
    expect(notifier.cancelledAll, isTrue);
    expect(tasks.all, isEmpty);
    expect(await settings.read(), AppSettings.defaults);
    expect((await usage.read(today)).captureCount, 0);
    expect(find.text('All data deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every row opens the screen the design points it at', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpSettings(tester);

    const Map<String, String> destinations = <String, String>{
      'Language': 'Language screen',
      'Subscription': 'Paywall screen',
      'Usage': 'Usage screen',
      'Privacy Policy': 'Privacy screen',
      'Terms of Service': 'Terms screen',
      'Help & Support': 'Help screen',
      'About': 'About screen',
    };

    for (final MapEntry<String, String> entry in destinations.entries) {
      await tester.tap(find.text(entry.key));
      await pumpSettled(tester);
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key} went somewhere else',
      );

      router.pop();
      await pumpSettled(tester);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
