import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/database/app_database.dart';

import 'database_test_kit.dart';

/// ⚠️ The cheapest bug this file catches: someone adds a column to
/// `tables.dart`, runs the app on a device that already has the database,
/// forgets to bump `schemaVersion`, and every query touching the new column
/// fails with `no such column` — on their users' phones and not on their own,
/// because their own install was created fresh after the change.
///
/// `validateDatabaseSchema` compares what `onCreate` actually produced against
/// what the generated code believes exists, so the mismatch surfaces here
/// instead of in a crash report.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('the created schema matches what the generated code expects', () async {
    await db.validateDatabaseSchema();
  });

  test(
    'schemaVersion is 1, and drift_schemas/ holds the matching snapshot',
    () {
      // A bump with no matching `drift_schema_vN.json` leaves the migration
      // harness with nothing to migrate from, which is how a broken migration
      // ships unnoticed.
      expect(db.schemaVersion, 1);
    },
  );

  test('the three tables are named what the rest of the app assumes', () async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();

    expect(
      rows.map((QueryRow row) => row.read<String>('name')).toList(),
      <String>['app_settings', 'tasks', 'usage_days'],
    );
  });

  test('every index the read path depends on exists', () async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'tasks' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();

    expect(
      rows.map((QueryRow row) => row.read<String>('name')).toList(),
      <String>[
        'tasks_completed_at',
        'tasks_due_date',
        'tasks_pending_due',
        'tasks_reminder_at',
      ],
    );
  });

  test('no hot query falls back to a full table scan', () async {
    // ⚠️ `tasks_pending_due` leads on `completed`, which is what every list
    // query filters on first, so all four of these are index seeks. What they
    // do *not* get is a free sort: the ordering key contains `IS NULL`
    // expressions, so SQLite builds a temp b-tree for ORDER BY. That is
    // deliberate and cheap here — the b-tree is over one user's open tasks, a
    // few hundred rows at most — but it is the reason to be suspicious of any
    // future change that makes these lists unbounded.
    Future<String> planOf(String sql, List<Variable<Object>> variables) async {
      final List<QueryRow> rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: variables)
          .get();
      return rows.map((QueryRow row) => row.data.values.join(' ')).join('\n');
    }

    const String order =
        'ORDER BY due_date IS NULL, due_date, '
        'due_minute_of_day IS NULL DESC, due_minute_of_day, sort_order';

    final List<String> plans = <String>[
      await planOf(
        'SELECT * FROM tasks WHERE completed = 0 '
        'AND (due_date IS NULL OR due_date <= ?) $order',
        <Variable<Object>>[Variable<String>('2026-03-11')],
      ),
      await planOf(
        'SELECT * FROM tasks WHERE completed = 0 AND due_date > ? $order',
        <Variable<Object>>[Variable<String>('2026-03-11')],
      ),
      await planOf(
        'SELECT * FROM tasks WHERE completed = 0 AND reminder_enabled = 1 '
        'AND reminder_at_local >= ? ORDER BY reminder_at_local LIMIT 64',
        <Variable<Object>>[Variable<String>('2026-03-11T10:00')],
      ),
      await planOf(
        'SELECT * FROM tasks WHERE completed = 1 '
        'ORDER BY completed_at_utc_ms DESC LIMIT 200',
        <Variable<Object>>[],
      ),
    ];

    for (final String plan in plans) {
      expect(plan, contains('USING INDEX'), reason: plan);
      expect(plan, isNot(contains('SCAN tasks\n')), reason: plan);
    }
  });
}
