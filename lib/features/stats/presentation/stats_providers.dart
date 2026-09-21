import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task_repository.dart';

final StreamProvider<TaskStats> taskStatsProvider = StreamProvider<TaskStats>((
  Ref ref,
) {
  return ref.watch(taskRepositoryProvider).watchStats(ref.watch(todayProvider));
});
