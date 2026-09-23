import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/settings_dao.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/core/database/daos/usage_dao.dart';
import 'package:tasuke_ai/core/logging/log.dart';

/// The single [AppDatabase] instance.
///
/// ⚠️ `ref.onDispose(db.close)` is not tidiness. Riverpod disposes a provider
/// when its `ProviderScope` goes away, which in tests is once per test case; a
/// database that is not closed keeps its background isolate and its file handle
/// alive, and the next test's `NativeDatabase` opens alongside it. On a real
/// device an un-closed connection survives a hot restart and the second one
/// hits the WAL lock of the first.
///
/// ⚠️ The close is guarded. Closing a database whose open failed rethrows
/// that failure, and the fatal-error screen disposes exactly that instance —
/// unguarded, it surfaced as an uncaught async error.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((
  Ref ref,
) {
  final AppDatabase database = AppDatabase(clock: ref.watch(clockProvider));
  ref.onDispose(
    () => unawaited(
      database.close().catchError((Object error) {
        Log.w('closing the database failed: ${error.runtimeType}');
      }),
    ),
  );
  return database;
});

/// Deletes the database file, for the fatal-error screen's reset.
///
/// A provider so a widget test can stand in for the file system.
final Provider<Future<void> Function()> databaseFileDeleterProvider =
    Provider<Future<void> Function()>((Ref ref) => AppDatabase.deleteFiles);

/// The DAOs are separate providers rather than reached through
/// `appDatabaseProvider.tasksDao` at call sites, so that a test can override
/// exactly one of them.
final Provider<TasksDao> tasksDaoProvider = Provider<TasksDao>(
  (Ref ref) => ref.watch(appDatabaseProvider).tasksDao,
);

final Provider<SettingsDao> settingsDaoProvider = Provider<SettingsDao>(
  (Ref ref) => ref.watch(appDatabaseProvider).settingsDao,
);

final Provider<UsageDao> usageDaoProvider = Provider<UsageDao>(
  (Ref ref) => ref.watch(appDatabaseProvider).usageDao,
);
