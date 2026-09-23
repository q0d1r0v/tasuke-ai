import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/lifecycle/app_lifecycle.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/home/presentation/date_labels.dart';
import 'package:tasuke_ai/features/home/presentation/home_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_actions.dart';
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
          const _PermissionsBanner(),
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

/// Says so when reminders cannot ring.
///
/// ⚠️ The string for this existed (`bannerNotificationsOff`) and nothing
/// rendered it. A user whose notification permission was never granted set a
/// reminder, saw its switch ON, and at the time got nothing — with no hint on
/// any screen that the OS was refusing every alarm.
///
/// Shown for a refusal only, not for "never asked": the app asks at the moment
/// a reminder is created, and a banner before that would nag about a
/// permission nobody has needed yet. Tapping it re-asks when the OS still
/// allows that, and opens the Settings app when it will not.
/// The warning that stays on Home while a required permission is off.
///
/// ⚠️ Not dismissible. The permissions screen is deliberately not a gate — a
/// hard gate is a dead end on iOS and an App Review rejection — so this banner
/// is what makes the permissions non-optional instead: it does not go away
/// until the gap is closed. It re-checks on every resume, because the usual
/// way to fix a permission is a trip to the Settings app.
class _PermissionsBanner extends ConsumerWidget {
  const _PermissionsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AppPermission> missing =
        ref.watch(missingPermissionsProvider).value ?? const <AppPermission>[];
    if (missing.isEmpty) return const SizedBox.shrink();

    // One gap gets its own words and is fixed in place, with one tap. Several
    // go to the permissions screen, where each is shown with its state.
    final bool several = missing.length > 1;
    final (String message, IconData icon) = several
        ? (context.l10n.bannerPermissionsMissing, Icons.error_outline_rounded)
        : switch (missing.single) {
            AppPermission.microphone => (
              context.l10n.bannerMicrophoneOff,
              Icons.mic_off_outlined,
            ),
            AppPermission.notifications => (
              context.l10n.bannerNotificationsOff,
              Icons.notifications_off_outlined,
            ),
            AppPermission.exactAlarm => (
              context.l10n.bannerExactAlarmOff,
              Icons.alarm_off_rounded,
            ),
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TasukeSpacing.gutter,
        0,
        TasukeSpacing.gutter,
        TasukeSpacing.md,
      ),
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: TasukeRadii.rField,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: TasukeRadii.rField,
            onTap: several
                ? () => context.push<void>(AppRoute.access.path)
                : () => _fix(context, ref, missing.single),
            child: TasukeBanner(
              message: message,
              icon: icon,
              tone: BannerTone.warning,
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _fix(
    BuildContext context,
    WidgetRef ref,
    AppPermission permission,
  ) async {
    final PermissionService permissions = ref.read(permissionServiceProvider);
    final String inSettings = context.l10n.permissionsTurnOnInSettings;
    final String openSettings = context.l10n.actionOpenSettings;

    final PermissionState state = await permissions.status(permission);
    if (state.needsSettings) {
      // ⚠️ A permanently denied permission cannot be re-requested: the call
      // silently no-ops. Settings is the only place the answer can change.
      await permissions.openSettings();
    } else {
      // For exact alarms this opens the "Alarms & reminders" page: Android has
      // no dialog for that permission.
      await permissions.request(permission);

      // ⚠️ Android can refuse without showing anything — "don't ask again",
      // or notifications below Android 13, where no prompt exists. The tap
      // must still visibly lead somewhere. Offered, not forced: a user who
      // has just pressed "Don't allow" is not thrown out of the app for it.
      final PermissionState after = await permissions.status(permission);
      if (after.needsSettings && context.mounted) {
        AppSnack.info(
          context,
          inSettings,
          action: (
            label: openSettings,
            onPressed: () => unawaited(permissions.openSettings()),
          ),
        );
      }
    }
    ref.invalidate(permissionStatusProvider(permission));
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.today, required this.tab});

  final LocalDate today;
  final HomeTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ Watched for the rebuild alone. The clock never notifies and Home
    // stays mounted for hours, so without this an app opened at 08:00 and
    // resumed at 20:00 still said "Good morning".
    ref.watch(appResumedProvider);
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
        // ⚠️ `center`, not `start`. The greeting is two lines (~48pt) and the
        // mark is 40pt, so aligning to the top leaves the mark floating above
        // the block it belongs to — it reads as a stray badge stuck to the
        // status bar rather than as the app's own header.
        crossAxisAlignment: CrossAxisAlignment.center,
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
                // ⚠️ No trailing emoji. It used to be interpolated here as a
                // Dart literal rather than living in the ARB, so it was invisible
                // to the hardcoded-strings guard, untranslatable, and read aloud
                // by VoiceOver as "sparkles" after every greeting.
                Text(context.l10n.homeTagline, style: TasukeTypography.titleLg),
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
      timeLabel: DateLabels.tileTime(context, task),
      onToggle: (bool value) => unawaited(
        // ⚠️ Through TaskActions, not the repository. The repository
        // deliberately does not touch the notifier, so a bare
        // `setCompleted` leaves the OS still holding an alarm for a task
        // the user has just ticked off.
        ref.read(taskActionsProvider).setCompleted(task.id, completed: value),
      ),
      onTap: () => context.push(taskDetailLocation(task.id)),
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
