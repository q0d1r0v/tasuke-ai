import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/database/daos/settings_dao.dart';
import 'package:tasuke_ai/core/database/daos/tasks_dao.dart';
import 'package:tasuke_ai/core/database/daos/usage_dao.dart';
import 'package:tasuke_ai/core/database/schema_versions.g.dart';
import 'package:tasuke_ai/core/database/tables.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

part 'app_database.g.dart';

/// How long a `usage_days` row is kept.
///
/// The quota only ever reads today, and the Usage screen shows a month. Ninety
/// days is generous enough that nobody notices the pruning and small enough
/// that the table cannot grow without bound on a device that is never
/// reinstalled.
const int kUsageRetentionDays = 90;

/// The one SQLite database. There is no other persistence in the app, and no
/// backend at all — this file is the user's only copy of their tasks.
@DriftDatabase(
  tables: <Type>[Tasks, SettingsEntries, UsageDays],
  daos: <Type>[TasksDao, SettingsDao, UsageDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({this.clock = const SystemClock()}) : super(_openConnection());

  /// An in-memory or otherwise caller-supplied executor.
  ///
  /// Tests pass `NativeDatabase.memory()`; a `FixedClock` alongside it makes
  /// the seeding and pruning in [beforeOpen] deterministic.
  AppDatabase.forTesting(super.executor, {this.clock = const SystemClock()});

  /// Only [beforeOpen] uses it — seeding and pruning both need a timestamp, and
  /// `DateTime.now()` is banned outside `core/clock`.
  final Clock clock;

  /// ⚠️ **Application Support, not Documents.**
  ///
  /// On iOS, `getApplicationDocumentsDirectory()` is the directory exposed in
  /// the Files app when `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`
  /// are on — and a user browsing their own phone can then find `tasuke.sqlite`
  /// and delete it. Application Support is not browsable.
  ///
  /// It IS still included in the iCloud/iTunes device backup, and that is
  /// deliberate rather than an oversight: there is no server, so the backup is
  /// the only thing standing between a lost phone and a lost task list. (The
  /// directory to use if we ever wanted it *excluded* would be Caches, which
  /// the OS is free to delete under storage pressure — catastrophic here.)
  static QueryExecutor _openConnection() => driftDatabase(
    name: _name,
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );

  /// `driftDatabase` stores the file as `<name>.sqlite` in the directory above.
  static const String _name = 'tasuke';

  /// Deletes the database file and its side files: the fatal-error screen's
  /// way out of a file that will not open.
  ///
  /// ⚠️ Close the instance first. A connection still open here can unlink or
  /// recreate the `-wal` under the next one.
  static Future<void> deleteFiles() async {
    final Directory directory = await getApplicationSupportDirectory();
    for (final String suffix in <String>['', '-wal', '-shm', '-journal']) {
      final File file = File(
        '${directory.path}${Platform.pathSeparator}$_name.sqlite$suffix',
      );
      if (file.existsSync()) await file.delete();
    }
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),

    // ⚠️ The step ladder has no steps yet, and it exists anyway.
    //
    // The alternative — adding migration machinery at the same moment as
    // the first real migration — means v2 is the first time this code path
    // has ever run, on devices holding data that cannot be re-downloaded
    // from anywhere. Wiring it at v1 costs one generated file now and makes
    // shipping v2 a matter of filling in `from1To2`, against a path the
    // migration test already exercises.
    //
    // Regenerating after a schemaVersion bump is three commands:
    //   dart run build_runner build
    //   dart run drift_dev schema dump lib/core/database/app_database.dart \
    //       drift_schemas/
    //   dart run drift_dev schema steps drift_schemas/ \
    //       lib/core/database/schema_versions.g.dart
    // (`.g.dart` so that `analysis_options.yaml`'s existing exclusion
    // covers it — it is generated code, even though it is a library rather
    // than a part.)
    onUpgrade: stepByStep(),

    beforeOpen: (OpeningDetails details) async {
      // ⚠️ Write-ahead logging, and it is not a micro-optimisation.
      //
      // The reminder scheduler reads this database on a background isolate
      // while the UI writes to it. In the default rollback journal a reader
      // and a writer exclude each other, so a save during a scheduling
      // sweep returns SQLITE_BUSY — which surfaces to the user as a Save
      // button that does nothing and a task that vanished. WAL lets the
      // reader carry on against the old snapshot.
      await customStatement('PRAGMA journal_mode = WAL');

      // Off by default in SQLite, per-connection, and not persisted in the
      // file. There are no foreign keys in v1; turning it on now means the
      // first one added is enforced instead of being decorative.
      await customStatement('PRAGMA foreign_keys = ON');

      final DateTime nowUtc = clock.nowUtc();
      if (details.wasCreated) {
        await settingsDao.seedDefaults(nowUtc: nowUtc);
      }

      // Pruning on open rather than on write: the app is opened far less
      // often than it is written to, and a row that outlives its window by
      // a few hours costs nothing.
      final LocalDate cutoff = LocalDate.today(clock.nowLocal())
          .addDays(-kUsageRetentionDays);
      await usageDao.pruneBefore(cutoff.toIso());
    },
  );
}
