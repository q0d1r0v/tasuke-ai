import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/features/reminders/domain/reminder_scheduler.dart';
import 'package:tasuke_ai/features/tasks/data/task_actions.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

import '../../helpers/fakes.dart';

/// Records the order of the two halves, because the order is the contract.
final class OrderedScheduler implements ReminderScheduler {
  OrderedScheduler(this._log);

  final List<String> _log;

  @override
  Future<SyncOutcome> sync() async {
    _log.add('sync');
    return const SyncOutcome(scheduled: 0, cancelled: 0, exact: true);
  }

  @override
  Future<void> cancelAll() async => _log.add('cancelAll');
}

void main() {
  late FakeTaskRepository tasks;
  late List<String> log;
  late TaskActions actions;

  setUp(() {
    tasks = FakeTaskRepository();
    log = <String>[];
    actions = TaskActions(tasks: tasks, reminders: OrderedScheduler(log));
  });

  test('ticking a task off re-syncs the OS alarms', () async {
    // ⚠️ The regression this exists for: the task-detail screen re-synced,
    // and the Home list — the most common place a task is ticked off — did
    // not. Hours later the phone buzzed about a task already finished.
    await actions.setCompleted('t-1', completed: true);

    expect(log, <String>['sync']);
  });

  test('un-ticking one re-syncs too, so the alarm comes back', () async {
    await actions.setCompleted('t-1', completed: false);

    expect(log, <String>[
      'sync',
    ], reason: 'the reverse direction was broken in exactly the same way');
  });

  test('the write lands before the sweep reads the rows', () async {
    // ⚠️ `sync()` re-reads the tasks to decide what the OS should hold, so a
    // sweep that overlaps the write plans against the state it is replacing.
    final List<String> order = <String>[];
    final TaskActions ordered = TaskActions(
      tasks: _RecordingRepository(order, tasks),
      reminders: OrderedScheduler(order),
    );

    await ordered.setCompleted('t-1', completed: true);

    expect(order, <String>['setCompleted', 'sync']);
  });
}

/// A pass-through that notes when the write happened.
///
/// `implements`, not `extends`: `FakeTaskRepository` is `final`, and only the
/// one method under test needs a body.
final class _RecordingRepository implements TaskRepository {
  _RecordingRepository(this._log, this._inner);

  final List<String> _log;
  final FakeTaskRepository _inner;

  @override
  Future<void> setCompleted(String id, {required bool completed}) async {
    _log.add('setCompleted');
    await _inner.setCompleted(id, completed: completed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not under test');
}
