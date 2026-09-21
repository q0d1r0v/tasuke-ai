@Tags(<String>['migration'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/database/app_database.dart';

import 'database_test_kit.dart';
import 'generated/schema.dart';

/// The migration harness, wired at v1 with nothing yet to migrate.
///
/// ⚠️ It exists now precisely because it has nothing to do. The alternative is
/// writing the first migration and the machinery to test it in the same change,
/// which means the first time anyone runs a migration is against real users'
/// data — data that has no copy anywhere, because this app has no backend.
///
/// Adding v2 is then three commands (see `app_database.dart`) plus one `test`
/// below of the shape:
///
/// ```dart
/// test('migrates v1 to v2', () async {
///   final InitializedSchema schema = await verifier.schemaAt(1);
///   // ... insert v1 rows through schema.rawDatabase ...
///   final AppDatabase db = AppDatabase.forTesting(schema.newConnection());
///   await verifier.migrateAndValidate(db, 2);
///   // ... assert the old rows survived ...
/// });
/// ```
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('every schema version in drift_schemas/ can be instantiated', () async {
    for (final int version in GeneratedHelper.versions) {
      final DatabaseConnection connection = await verifier.startAt(version);
      final AppDatabase db = AppDatabase.forTesting(
        connection,
        clock: FixedClock(kTestNowLocal),
      );
      addTearDown(db.close);

      // Opening it runs `beforeOpen`, which is itself part of what a migration
      // has to survive — a seed or a prune that throws bricks the launch just
      // as thoroughly as a bad `ALTER TABLE`.
      await db.customSelect('SELECT 1').get();
    }
  });

  test('a database created at the current version validates', () async {
    final InitializedSchema schema = await verifier.schemaAt(
      GeneratedHelper.versions.last,
    );
    final AppDatabase db = AppDatabase.forTesting(
      schema.newConnection(),
      clock: FixedClock(kTestNowLocal),
    );
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
  });

  test('the snapshot set covers every version up to schemaVersion', () {
    // A `schemaVersion` bump with no new `drift_schema_vN.json` leaves
    // `stepByStep` with a hole it only discovers on a user's device.
    final AppDatabase db = openTestDatabase();
    addTearDown(db.close);

    expect(GeneratedHelper.versions, <int>[
      for (int v = 1; v <= db.schemaVersion; v++) v,
    ]);
  });
}
