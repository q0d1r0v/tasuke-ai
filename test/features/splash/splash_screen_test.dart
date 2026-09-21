import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/splash/presentation/splash_screen.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The splash is the only screen the user can reach with a broken database, so
/// it carries the two things that must work in that state: the brand while the
/// bootstrap runs, and a way out when it fails.
void main() {
  late FakeTaskRepository tasks;
  late FakeSettingsRepository settings;
  late FakeUsageRepository usage;
  late FakeLocalNotifier notifier;

  setUp(() {
    tasks = FakeTaskRepository();
    settings = FakeSettingsRepository();
    usage = FakeUsageRepository();
    notifier = FakeLocalNotifier();
  });

  tearDown(() {
    tasks.dispose();
    settings.dispose();
    usage.dispose();
    notifier.dispose();
  });

  /// The fakes the reset path writes through. The reset itself is deliberately
  /// NOT stubbed: what is worth proving is that the button on this screen
  /// really reaches the notifier and the repositories.
  List<Override> overridesWith(Override bootstrap) => <Override>[
    ...defaultOverrides(notifier: notifier),
    bootstrap,
    taskRepositoryProvider.overrideWithValue(tasks),
    settingsRepositoryProvider.overrideWithValue(settings),
    usageRepositoryProvider.overrideWithValue(usage),
  ];

  testWidgets('holds the brand, and nothing else, while the boot runs', (
    WidgetTester tester,
  ) async {
    // A future that never completes is the whole point: this is the frame the
    // user actually looks at on a cold start.
    final Completer<BootstrapResult> pending = Completer<BootstrapResult>();

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith((Ref ref) => pending.future),
      ),
    );

    expect(find.byType(TasukeLogo), findsOneWidget);
    expect(find.text('Tasuke AI'), findsOneWidget);
    expect(find.text('Voice to Tasks'), findsOneWidget);
    expect(find.text('Speak. Plan. Done.'), findsOneWidget);

    // No spinner, by design: over a brand mark it reads as "something is
    // wrong" rather than as "loading".
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("Tasuke can't open its database"), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a boot that fails becomes the fatal-error screen in place', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith(
          (Ref ref) async => throw StateError('database is not a database'),
        ),
      ),
    );

    expect(find.text("Tasuke can't open its database"), findsOneWidget);
    expect(
      find.text("This usually means the app's storage was damaged."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Reset app data'), findsOneWidget);

    // The brand copy gives way rather than sitting above an error nobody can
    // act on from a splash screen.
    expect(find.text('Speak. Plan. Done.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Try again re-runs the bootstrap rather than the screen', (
    WidgetTester tester,
  ) async {
    int attempts = 0;

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith((Ref ref) async {
          attempts++;
          throw StateError('still broken');
        }),
      ),
    );
    expect(attempts, 1);

    await tester.tap(find.text('Try again'));
    await pumpSettled(tester);

    expect(attempts, 2);
    // Still failing, so the user is still offered both ways out.
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Reset app data'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelling the reset leaves every task on the device', (
    WidgetTester tester,
  ) async {
    tasks.seed(<Task>[_task('task-1', 'Send the build to James')]);

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith(
          (Ref ref) async => throw StateError('database is not a database'),
        ),
      ),
    );

    await tester.tap(find.text('Reset app data'));
    await pumpSettled(tester);
    expect(find.text('Delete everything?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await pumpSettled(tester);

    // There is no backend: a reset really is the user's data, so a dismissed
    // dialog must mean "don't".
    expect(tasks.all, hasLength(1));
    expect(notifier.cancelledAll, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirming the reset clears the alarms, then the data, then '
      'retries the boot', (WidgetTester tester) async {
    int attempts = 0;
    tasks.seed(<Task>[_task('task-1', 'Send the build to James')]);

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith((Ref ref) async {
          attempts++;
          throw StateError('still broken');
        }),
      ),
    );

    await tester.tap(find.text('Reset app data'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    expect(tasks.all, isEmpty);
    // ⚠️ The alarms go first. A task row deleted while its alarm is still
    // scheduled leaves a notification that opens a task that no longer exists.
    expect(notifier.cancelledAll, isTrue);
    expect(attempts, 2, reason: 'the boot is retried against the fresh file');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Task _task(String id, String title) {
  final DateTime at = DateTime.utc(2026, 9, 21, 9);
  return Task(id: id, title: title, createdAt: at, updatedAt: at);
}
