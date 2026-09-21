import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/home/presentation/home_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeTab tab = ref.watch(homeTabProvider);
    final LocalDate today = ref.watch(todayProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(today: today, tab: tab),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TasukeSpacing.gutter,
            ),
            child: SegmentedTabs(
              labels: <String>[
                context.l10n.homeTabToday,
                context.l10n.homeTabUpcoming,
                context.l10n.homeTabCompleted,
              ],
              selected: tab.index,
              onSelected: (int index) => ref
                  .read(homeTabProvider.notifier)
                  .select(HomeTab.values[index]),
            ),
          ),
          const SizedBox(height: TasukeSpacing.lg),
          Expanded(
            child: switch (tab) {
              HomeTab.today => const _TodayList(),
              HomeTab.upcoming => const _GroupedList(completed: false),
              HomeTab.completed => const _GroupedList(completed: true),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.today, required this.tab});

  final LocalDate today;
  final HomeTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime now = ref.watch(clockProvider).nowLocal();

    // On Today the header is the greeting from the design sheet. On the other
    // two segments it collapses to the segment's own title — which is what
    // frames 9 and 10 of the sheet show.
    if (tab != HomeTab.today) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          TasukeSpacing.gutter,
          TasukeSpacing.lg,
          TasukeSpacing.gutter,
          TasukeSpacing.lg,
        ),
        child: Text(
          tab == HomeTab.upcoming
              ? context.l10n.homeTabUpcoming
              : context.l10n.homeTabCompleted,
          style: TasukeTypography.titleLg,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TasukeSpacing.gutter,
        TasukeSpacing.lg,
        TasukeSpacing.gutter,
        TasukeSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  DateLabels.greeting(context, now),
                  style: TasukeTypography.bodyMd.copyWith(
                    color: TasukeColors.inkMuted,
                  ),
                ),
                const SizedBox(height: TasukeSpacing.xs),
                Text(
                  '${context.l10n.homeTagline} ✨',
                  style: TasukeTypography.titleLg,
                ),
              ],
            ),
          ),
          const SizedBox(width: TasukeSpacing.md),
          const TasukeLogo(size: 40),
        ],
      ),
    );
  }
}

class _TodayList extends ConsumerWidget {
  const _TodayList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LocalDate today = ref.watch(todayProvider);

    return AsyncValueView<List<Task>>(
      value: ref.watch(todayTasksProvider),
      data: (List<Task> tasks) {
        if (tasks.isEmpty) {
          return EmptyState(
            title: context.l10n.emptyTodayTitle,
            message: context.l10n.emptyTodayBody,
            icon: Icons.mic_none_rounded,
          );
        }
        return ListView.separated(
          padding: _listPadding(context),
          itemCount: tasks.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: TasukeSpacing.cardGap),
          itemBuilder: (_, int index) =>
              _Tile(task: tasks[index], today: today),
        );
      },
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LocalDate today = ref.watch(todayProvider);

    return AsyncValueView<List<TaskGroup>>(
      value: ref.watch(
        completed ? completedTaskGroupsProvider : upcomingTaskGroupsProvider,
      ),
      data: (List<TaskGroup> groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: completed
                ? context.l10n.emptyCompletedTitle
                : context.l10n.emptyUpcomingTitle,
            message: completed
                ? context.l10n.emptyCompletedBody
                : context.l10n.emptyUpcomingBody,
            icon: completed
                ? Icons.check_circle_outline_rounded
                : Icons.calendar_today_rounded,
          );
        }

        return ListView.builder(
          padding: _listPadding(context),
          itemCount: groups.length,
          itemBuilder: (_, int groupIndex) {
            final TaskGroup group = groups[groupIndex];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (groupIndex > 0) const SizedBox(height: TasukeSpacing.xl),
                SectionHeader(
                  label: DateLabels.groupHeader(context, group, today),
                ),
                const SizedBox(height: TasukeSpacing.sectionGap),
                for (int i = 0; i < group.tasks.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: TasukeSpacing.cardGap),
                  _Tile(task: group.tasks[i], today: today),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.task, required this.today});

  final Task task;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TaskListTile(
      task: task,
      relativeDayLabel: task.due == null
          ? context.l10n.dateSomeday
          : DateLabels.day(context, task.due!.date, today),
      timeLabel: task.due?.time == null
          ? context.l10n.taskAllDay
          : DateLabels.time(context, task.due!.time!),
      onToggle: (bool value) => ref
          .read(taskRepositoryProvider)
          .setCompleted(task.id, completed: value),
      onTap: () => context.push('/task/${task.id}'),
    );
  }
}

/// ⚠️ The nav band floats over the list (`extendBody: true` in HomeShell), so
/// every scroll view under it must reserve that height itself — otherwise the
/// last task sits permanently behind the mic button.
EdgeInsets _listPadding(BuildContext context) => EdgeInsets.fromLTRB(
  TasukeSpacing.gutter,
  0,
  TasukeSpacing.gutter,
  TasukeMetrics.navBandHeightOf(context) + TasukeSpacing.lg,
);
