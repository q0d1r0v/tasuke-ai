import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/bootstrap/app_bootstrap.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
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

  /// How many times a database instance was built.
  late int databasesBuilt;

  /// What the fatal reset's file deletion saw, in order.
  late List<String> events;

  /// Replaces the real file deletion; set to throw to model a failed one.
  late Future<void> Function() deleteFiles;

  setUp(() {
    databasesBuilt = 0;
    events = <String>[];
    deleteFiles = () async {
      events.add(notifier.cancelledAll ? 'delete after cancel' : 'delete');
    };
  });

  /// The fakes the reset path writes through. The reset itself is deliberately
  /// NOT stubbed: what is worth proving is that the button on this screen
  /// really reaches the notifier and the file.
  ///
  /// ⚠️ The database is a provider that throws, never a real drift instance:
  /// one opened inside `testWidgets` deadlocks (see README). A throwing build
  /// is also exactly what the fatal screen is for.
  List<Override> overridesWith(Override bootstrap) => <Override>[
    ...defaultOverrides(settings: settings, notifier: notifier),
    bootstrap,
    taskRepositoryProvider.overrideWithValue(tasks),
    usageRepositoryProvider.overrideWithValue(usage),
    appDatabaseProvider.overrideWith((Ref ref) {
      databasesBuilt++;
      throw StateError('database is not a database');
    }),
    databaseFileDeleterProvider.overrideWithValue(() => deleteFiles()),
  ];

  /// A boot that fails the way a broken database does: through the instance.
  ///
  /// ⚠️ `read`, not `watch`, like the real boot's `databaseHealthProvider`
  /// read. A watch re-runs the boot when the reset invalidates the database,
  /// which hides a screen that never retries it.
  Override brokenBoot(void Function() onAttempt) =>
      appBootstrapProvider.overrideWith((Ref ref) async {
        onAttempt();
        ref.read<AppDatabase>(appDatabaseProvider);
        return const BootstrapResult();
      });

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

  testWidgets('Try again builds a fresh database, not the poisoned one', (
    WidgetTester tester,
  ) async {
    // ⚠️ drift caches a failed open on the instance and rethrows it on every
    // later query, so a retry against the same instance could never succeed.
    int attempts = 0;
    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(brokenBoot(() => attempts++)),
    );
    expect(databasesBuilt, 1);

    await tester.tap(find.text('Try again'));
    await pumpSettled(tester);

    expect(attempts, 2);
    expect(databasesBuilt, 2);

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

  testWidgets('confirming the reset deletes the file, then the alarms, then '
      'retries the boot on a fresh database', (WidgetTester tester) async {
    int attempts = 0;
    tasks.seed(<Task>[_task('task-1', 'Send the build to James')]);

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(brokenBoot(() => attempts++)),
    );

    await tester.tap(find.text('Reset app data'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    // ⚠️ The file, not the rows: the rows are behind the connection that
    // would not open, so a reset through the repositories threw and did
    // nothing — after it had already cancelled every reminder.
    expect(events, <String>['delete']);
    expect(tasks.all, hasLength(1), reason: 'nothing ran through the database');
    expect(notifier.cancelledAll, isTrue);
    expect(attempts, 2, reason: 'the boot is retried against the fresh file');
    expect(databasesBuilt, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reset that cannot delete the file says so and keeps the '
      'reminders', (WidgetTester tester) async {
    int attempts = 0;
    deleteFiles = () async => throw const FileSystemException('read-only');

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(brokenBoot(() => attempts++)),
    );

    await tester.tap(find.text('Reset app data'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    expect(
      find.text(
        "Couldn't reset the app data. Restart Tasuke AI and try again.",
      ),
      findsOneWidget,
    );
    expect(notifier.cancelledAll, isFalse);
    expect(attempts, 1);
    expect(find.text('Reset app data'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reset that ends after a retry already recovered does not '
      'touch the gone screen', (WidgetTester tester) async {
    // ⚠️ The fatal screen stays up while a retry boot runs, so a reset can
    // start on it and end after it is gone. `ref` on an unmounted widget
    // throws, and inside the unawaited reset that is an uncaught error.
    int attempts = 0;
    final Completer<BootstrapResult> retry = Completer<BootstrapResult>();
    final Completer<void> deleting = Completer<void>();
    deleteFiles = () => deleting.future;

    await pumpScreen(
      tester,
      const SplashScreen(),
      overrides: overridesWith(
        appBootstrapProvider.overrideWith((Ref ref) async {
          attempts++;
          if (attempts == 1) throw StateError('database is locked');
          return retry.future;
        }),
      ),
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Reset app data'), findsOneWidget);

    await tester.tap(find.text('Reset app data'));
    await pumpSettled(tester);
    await tester.tap(find.text('Delete'));
    await pumpSettled(tester);

    // The retry lands while the file is still being deleted.
    retry.complete(const BootstrapResult());
    await pumpSettled(tester);
    expect(find.text('Reset app data'), findsNothing);

    deleting.complete();
    await pumpSettled(tester);

    expect(tester.takeException(), isNull);
    expect(notifier.cancelledAll, isTrue);
    expect(attempts, 2, reason: 'the boot already resolved; nothing to retry');
    expect(find.text('Speak. Plan. Done.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Task _task(String id, String title) {
  final DateTime at = DateTime.utc(2026, 9, 21, 9);
  return Task(id: id, title: title, createdAt: at, updatedAt: at);
}
