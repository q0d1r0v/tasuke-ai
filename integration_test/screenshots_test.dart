import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/app.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/storage/pref_keys.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/home/presentation/home_providers.dart';
import 'package:tasuke_ai/features/home/presentation/home_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

/// Captures the store listing screenshots from a real device.
///
///     tool/boot_emulator.sh
///     flutter drive --driver=test_driver/integration_test.dart \
///       --target=integration_test/screenshots_test.dart -d emulator-5554 --profile
///
/// Run through `flutter drive`, not `flutter test`: the driver is what pulls the
/// captured bytes off the device and writes them to `store/screenshots/`.
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A Wednesday at 09:41 — the time every phone in every store listing shows,
  // and a midweek date so "Tomorrow" and "Friday" are both unambiguous.
  final Clock clock = FixedClock(DateTime(2026, 4, 22, 9, 41));
  final LocalDate today = LocalDate.today(clock.nowLocal());

  /// ⚠️ `convertFlutterSurfaceToImage()` is called ONCE for the whole run, in
  /// the test body — calling it per screenshot asserts
  /// "Surface already converted to an image" on the second one.
  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('store screenshots', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefKeys.onboardingSeen: true,
      PrefKeys.permissionsPrimerSeen: true,
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(preferences),
          clockProvider.overrideWithValue(clock),
          // A fresh simulator has granted nothing, and the home banner that
          // says so would sit on top of every listing screenshot.
          missingPermissionsProvider.overrideWith(
            (Ref ref) async => const <AppPermission>[],
          ),
        ],
        child: const TasukeApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    final TaskRepository repository = container.read(taskRepositoryProvider);
    await repository.deleteAll();

    // The list from the design sheet, so the screenshots and the mockup agree.
    Future<void> seed(
      String title,
      LocalDate date,
      int? minute, {
      bool completed = false,
    }) async {
      final Task task = await repository.create(
        TaskDraft(
          draftId: 'shot-${title.hashCode}',
          title: title,
          date: date,
          time: minute == null ? null : LocalTimeOfDay(minute),
          hasReminder: minute != null,
          source: TaskSource.voice,
        ),
        allDayReminderMinute: 9 * 60,
      );
      if (completed) {
        await repository.setCompleted(task.id, completed: true);
      }
    }

    await seed('Design app UI', today, 10 * 60);
    await seed('Send the build to James', today, 15 * 60);
    await seed('Gym workout', today, 19 * 60);
    await seed('Read a book', today, 21 * 60);
    await seed('Check App Store', today.addDays(3), null);
    await seed('Update app screenshots', today.addDays(6), null);
    await seed('Plan marketing', today.addDays(7), null);
    await seed('Team meeting', today.addDays(8), 11 * 60);
    await seed('Buy groceries', today.addDays(-1), null, completed: true);
    await seed('Call Mom', today.addDays(-2), null, completed: true);
    await seed('Update CV', today.addDays(-3), null, completed: true);

    await tester.pumpAndSettle();
    await shoot(tester, '01_home_today');

    container.read(homeTabProvider.notifier).select(HomeTab.upcoming);
    await shoot(tester, '02_upcoming');

    container.read(homeTabProvider.notifier).select(HomeTab.completed);
    await shoot(tester, '03_completed');

    container.read(homeTabProvider.notifier).select(HomeTab.today);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await shoot(tester, '04_stats');

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await shoot(tester, '05_settings');

    await repository.deleteAll();
  });
}
