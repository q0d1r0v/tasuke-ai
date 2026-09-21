import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/daos/settings_dao.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/core/database/daos/usage_dao.dart';

/// The single [AppDatabase] instance.
///
/// ⚠️ `ref.onDispose(db.close)` is not tidiness. Riverpod disposes a provider
/// when its `ProviderScope` goes away, which in tests is once per test case; a
/// database that is not closed keeps its background isolate and its file handle
/// alive, and the next test's `NativeDatabase` opens alongside it. On a real
/// device an un-closed connection survives a hot restart and the second one
/// hits the WAL lock of the first.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((
  Ref ref,
) {
  final AppDatabase database = AppDatabase(clock: ref.watch(clockProvider));
  ref.onDispose(database.close);
  return database;
});

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
