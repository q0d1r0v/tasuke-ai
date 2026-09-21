import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/features/tasks/data/drift_task_repository.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

/// The app's [TaskRepository].
///
/// Exposed as the interface, not as [DriftTaskRepository]: a widget test
/// overrides this with a list-backed fake and never opens a database, which is
/// the difference between a 40 ms test and a 400 ms one.
final Provider<TaskRepository> taskRepositoryProvider =
    Provider<TaskRepository>(
      (Ref ref) => DriftTaskRepository(
        dao: ref.watch(tasksDaoProvider),
        clock: ref.watch(clockProvider),
      ),
    );
