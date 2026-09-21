import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_group.dart';

/// Turns dates into the strings the design shows.
///
/// Lives in the presentation layer because every one of these is an ARB lookup
/// or a locale-aware `intl` format, and the domain has no `BuildContext`.
abstract final class DateLabels {
  /// "Today" / "Tomorrow" / "Fri" / "26 Sep".
  static String day(BuildContext context, LocalDate date, LocalDate today) {
    final int delta = date.differenceInDays(today);
    if (delta == 0) return context.l10n.dateToday;
    if (delta == 1) return context.l10n.dateTomorrow;
    if (delta == -1) return context.l10n.dateYesterday;
    final DateTime dt = date.toDateTimeLocal();
    if (delta > 1 && delta <= 6) {
      return DateFormat.EEEE(_locale(context)).format(dt);
    }
    if (date.year == today.year) {
      return DateFormat.MMMd(_locale(context)).format(dt);
    }
    return DateFormat.yMMMd(_locale(context)).format(dt);
  }

  /// "3:00 PM" — ⚠️ through `DateFormat.jm`, never a hardcoded `'h:mm a'`.
  /// Most of Europe writes 15:00 with no meridiem, and a hardcoded pattern gets
  /// that wrong the day a second locale ships.
  static String time(BuildContext context, LocalTimeOfDay time) {
    final DateTime dt = DateTime(2000, 1, 1, time.hour, time.minute);
    return DateFormat.jm(_locale(context)).format(dt);
  }

  /// The task row's meta line: "Today, 10:00 AM" or "Today · All day".
  static String taskMeta(BuildContext context, Task task, LocalDate today) {
    final TaskDue? due = task.due;
    if (due == null) return context.l10n.dateSomeday;
    final String dayLabel = day(context, due.date, today);
    final LocalTimeOfDay? at = due.time;
    if (at == null) {
      return context.l10n.taskMetaRelative(dayLabel, context.l10n.taskAllDay);
    }
    return context.l10n.taskMetaRelative(dayLabel, time(context, at));
  }

  /// The section header above a group on Upcoming and Completed.
  static String groupHeader(
    BuildContext context,
    TaskGroup group,
    LocalDate today,
  ) {
    return switch (group.label) {
      TaskGroupLabel.today => context.l10n.dateToday,
      TaskGroupLabel.tomorrow => context.l10n.dateTomorrow,
      TaskGroupLabel.weekday => DateFormat.EEEE(
        _locale(context),
      ).format(group.date.toDateTimeLocal()),
      TaskGroupLabel.nextWeek => context.l10n.dateNextWeek,
      TaskGroupLabel.later ||
      TaskGroupLabel.completedOn => day(context, group.date, today),
    };
  }

  static String greeting(BuildContext context, DateTime now) {
    if (now.hour < 12) return context.l10n.homeGreetingMorning;
    if (now.hour < 18) return context.l10n.homeGreetingAfternoon;
    return context.l10n.homeGreetingEvening;
  }

  static String _locale(BuildContext context) =>
      Localizations.localeOf(context).toLanguageTag();
}
