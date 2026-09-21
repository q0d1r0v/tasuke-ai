import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

/// Which segment of the Home screen is showing.
///
/// A provider, not a route. Three routes would add a back-stack entry per tap,
/// so the system back button would walk the user through their own tab history
/// — which no frame of the design shows.
enum HomeTab { today, upcoming, completed }

final NotifierProvider<HomeTabController, HomeTab> homeTabProvider =
    NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

final class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.today;

  void select(HomeTab tab) => state = tab;
}

final StreamProvider<List<Task>> todayTasksProvider =
    StreamProvider<List<Task>>((Ref ref) {
      return ref
          .watch(taskRepositoryProvider)
          .watchToday(ref.watch(todayProvider));
    });

final StreamProvider<List<TaskGroup>> upcomingTaskGroupsProvider =
    StreamProvider<List<TaskGroup>>((Ref ref) {
      return ref
          .watch(taskRepositoryProvider)
          .watchUpcoming(ref.watch(todayProvider));
    });

final StreamProvider<List<TaskGroup>> completedTaskGroupsProvider =
    StreamProvider<List<TaskGroup>>((Ref ref) {
      return ref
          .watch(taskRepositoryProvider)
          .watchCompleted(ref.watch(todayProvider), limit: 200);
    });
