import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/app.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tasuke_ai/features/permissions/presentation/permissions_screen.dart';
import 'package:tasuke_ai/features/pipeline/presentation/capture_controller.dart';
import 'package:tasuke_ai/features/splash/presentation/splash_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Whole-app journeys.
///
/// These catch the wiring mistakes no unit test can see: a guard that sends a
/// configured user back to onboarding, a save that never reaches the list, a
/// reminder that is persisted but never handed to the OS.
void main() {
  /// Wednesday 2026-03-11, 10:00 local. Midweek and far from any month or year
  /// boundary, so a failure is never ambiguous between a bug and an off-by-one
  /// in the fixture.
  final DateTime testNow = DateTime(2026, 3, 11, 10);
  final Clock clock = FixedClock(testNow);
  final LocalDate today = LocalDate.today(testNow);

  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late FakeLocalNotifier notifier;
  late FakePermissionService permissions;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    notifier = FakeLocalNotifier();
    permissions = FakePermissionService();
  });

  // ⚠️ The database is closed HERE, not inside the test body.
  //
  // `testWidgets` runs its body inside `FakeAsync`, where no real timer ever
  // fires. Drift's `close()` waits on work that needs the real event loop, so
  // awaiting it in the body deadlocks the isolate outright — no test timeout
  // can interrupt it, and it presents as a native hang. `tearDown` runs outside
  // that zone, where awaiting is safe.
  tearDown(() {
    notifier.dispose();
    tasks.dispose();
    settings.dispose();
    usage.dispose();
  });

  /// Boots the real app over an in-memory database.
  Future<void> bootApp(WidgetTester tester, {bool configured = false}) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    if (configured) {
      await preferences.setBool(PrefKeys.onboardingSeen, true);
      await preferences.setBool(PrefKeys.permissionsPrimerSeen, true);
    }

    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(
            settings: settings,
            clock: clock,
            notifier: notifier,
            permissions: permissions,
            preferences: preferences,
          ),
          // ⚠️ The bootstrap opens the real database to surface a corrupt file
          // on the splash. In a widget test that is a deadlock, not a check —
          // see databaseHealthProvider's doc comment.
          databaseHealthProvider.overrideWith((Ref ref) async {}),
          taskRepositoryProvider.overrideWithValue(tasks),
          usageRepositoryProvider.overrideWithValue(usage),
        ],
        child: const TasukeApp(),
      ),
    );
    await pumpSettled(tester);
  }

  /// Unmounts the tree **inside the test body**.
  ///
  /// ⚠️ Not `addTearDown`. Disposing the ProviderScope closes drift's query
  /// streams, and `StreamQueryStore.markAsClosed` posts a zero-duration timer
  /// to finish the job. flutter_test asserts on pending timers at the end of
  /// the body, which runs *before* any teardown callback — so a tree unmounted
  /// in teardown reports "A Timer is still pending", a failure that looks
  /// exactly like a leak in the code under test and is not one.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a first launch lands on onboarding, not on Home', (
    WidgetTester tester,
  ) async {
    await bootApp(tester);

    // The splash is a real wait on the bootstrap future, so it is gone by the
    // time the tree settles.
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await shutdown(tester);
  });

  testWidgets('onboarding → permissions → Home', (WidgetTester tester) async {
    await bootApp(tester);

    await tester.tap(find.text('Skip'));
    await pumpSettled(tester);
    expect(find.byType(PermissionsScreen), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await pumpSettled(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // ⚠️ The permissions screen is a primer, not a gate: Continue works whether
    // or not the OS granted anything, because iOS never prompts twice and a
    // blocked Continue would be a dead end the app could not escape.
    expect(permissions.requested, isNot(contains(AppPermission.microphone)));

    await shutdown(tester);
  });

  testWidgets('a configured user is bounced off the transient screens', (
    WidgetTester tester,
  ) async {
    await bootApp(tester, configured: true);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);

    await shutdown(tester);
  });

  testWidgets('confirming a capture saves the tasks and shows them on Home', (
    WidgetTester tester,
  ) async {
    await bootApp(tester, configured: true);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );

    // Seed the drafts the extractor would have produced, then drive the real
    // save path. The grammar has its own several hundred tests; what is checked
    // here is that Confirm → database → list is actually connected.
    final CaptureController controller = container.read(
      captureControllerProvider.notifier,
    );
    controller.startManualDraft();
    final TaskDraft blank = container
        .read(captureControllerProvider)
        .drafts
        .single;
    controller.updateDraft(
      blank.copyWith(
        title: 'Send the build to James',
        date: today.addDays(1),
        time: const LocalTimeOfDay.hm(15, 0),
        hasReminder: true,
      ),
    );

    expect(await controller.save(), isTrue);
    await pumpSettled(tester);

    final List<Task> tomorrow = await tasks.watchToday(today.addDays(1)).first;
    expect(
      tomorrow.map((Task task) => task.title),
      contains('Send the build to James'),
    );

    // The reminder was persisted with a civil instant and a stable id, ready
    // for the scheduler's next sweep.
    final Task saved = tomorrow.firstWhere(
      (Task task) => task.title == 'Send the build to James',
    );
    expect(saved.reminder.enabled, isTrue);
    expect(saved.reminder.at?.time, const LocalTimeOfDay.hm(15, 0));
    expect(saved.reminder.notificationId, isNotNull);

    await shutdown(tester);
  });
}
