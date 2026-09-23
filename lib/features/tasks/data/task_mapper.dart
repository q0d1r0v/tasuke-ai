import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/database/app_database.dart';
import 'package:tasuke_ai/core/database/converters.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

/// The **only** place a Drift row becomes a [Task], and the only place a [Task]
/// becomes a row.
///
/// One mapper rather than a `fromRow` on the entity, because the entity lives
/// in `domain/` and may not import Drift. One mapper rather than several,
/// because the fields that are easy to get wrong — the fold of `title_folded`,
/// the reminder resolution, the null-vs-all-day distinction — have to be got
/// wrong in exactly one place before anyone notices.
abstract final class TaskMapper {
  static Task toTask(TaskRow row) {
    final LocalDate? dueDate = row.dueDate;
    return Task(
      id: row.id,
      title: row.title,
      notes: row.notes,
      // `dueDate == null` is "someday"; `dueMinuteOfDay == null` with a date is
      // "all day". Collapsing the two loses the difference between a task the
      // user never dated and one they dated but did not time.
      due: dueDate == null
          ? null
          : TaskDue(
              date: dueDate,
              time: LocalTimeOfDay.tryFromMinutes(row.dueMinuteOfDay),
            ),
      reminder: TaskReminder(
        enabled: row.reminderEnabled,
        leadMinutes: row.reminderLeadMinutes,
        at: row.reminderAtLocal,
        notificationId: row.notificationId,
      ),
      completed: row.completed,
      completedAt: row.completedAtUtcMs,
      createdAt: row.createdAtUtcMs,
      updatedAt: row.updatedAtUtcMs,
      source: TaskSource.fromName(row.source),
      sourceTranscript: row.sourceTranscript,
      captureId: row.captureId,
      sortOrder: row.sortOrder,
    );
  }

  static List<Task> toTasks(List<TaskRow> rows) =>
      rows.map(toTask).toList(growable: false);

  /// A full-row companion: every column is present, so this is safe for both
  /// `INSERT` and a whole-row `UPDATE`.
  ///
  /// ⚠️ `title_folded` is derived here and never accepted from a caller. A
  /// caller that passed its own fold could pass a stale one, and a row whose
  /// fold does not match its title is invisible to search while looking
  /// perfectly normal in every list.
  static TasksCompanion toCompanion(Task task) => TasksCompanion(
    id: Value<String>(task.id),
    title: Value<String>(task.title),
    titleFolded: Value<String>(foldForSearch(task.title)),
    notes: Value<String?>(task.notes),
    dueDate: Value<LocalDate?>(task.due?.date),
    dueMinuteOfDay: Value<int?>(task.due?.time?.minuteOfDay),
    reminderEnabled: Value<bool>(task.reminder.enabled),
    reminderLeadMinutes: Value<int>(task.reminder.leadMinutes),
    reminderAtLocal: Value<LocalDateTime?>(task.reminder.at),
    notificationId: Value<int?>(task.reminder.notificationId),
    completed: Value<bool>(task.completed),
    completedAtUtcMs: Value<DateTime?>(task.completedAt),
    createdAtUtcMs: Value<DateTime>(task.createdAt),
    updatedAtUtcMs: Value<DateTime>(task.updatedAt),
    source: Value<String>(task.source.name),
    sourceTranscript: Value<String?>(task.sourceTranscript),
    captureId: Value<String?>(task.captureId),
    sortOrder: Value<int>(task.sortOrder),
  );

  /// Turns an edited [TaskDraft] into the [Task] that will be written.
  ///
  /// [notificationId] is passed in rather than minted here because it comes
  /// from a counter in the database, and this function is pure — which is what
  /// makes the reminder arithmetic below testable without a database.
  static Task fromDraft(
    TaskDraft draft, {
    required String id,
    required String? captureId,
    required int allDayReminderMinute,
    required DateTime nowUtc,
    int? notificationId,
    int sortOrder = 0,
  }) {
    final LocalDate? date = draft.date;
    final TaskDue? due = date == null
        ? null
        : TaskDue(date: date, time: draft.time);

    // A reminder with nothing to fire against is not a reminder. The Confirm
    // card can leave `hasReminder` on while the user clears the date, and a row
    // with `reminder_enabled = 1` and `reminder_at_local = NULL` would be
    // picked up by the scheduler's orphan sweep forever.
    final bool enabled = draft.hasReminder && due != null;

    return Task(
      id: id,
      title: TaskTitle.normalise(draft.title),
      due: due,
      reminder: enabled
          ? TaskReminder(
              enabled: true,
              at: resolveReminderAt(
                due,
                allDayReminderMinute: allDayReminderMinute,
                now: LocalDateTime.fromLocal(nowUtc.toLocal()),
              ),
              notificationId: notificationId,
            )
          : TaskReminder.none,
      createdAt: nowUtc,
      updatedAt: nowUtc,
      source: draft.source,
      sourceTranscript: draft.sourceTranscript,
      captureId: captureId,
      sortOrder: sortOrder,
    );
  }

  /// `due date + (time ?? allDayReminderMinute) - leadMinutes`, as a civil
  /// date-time.
  ///
  /// ⚠️ The subtraction goes through [LocalDateTime.subtractMinutes], which
  /// rolls the **date** back when it crosses midnight. A 30-minute lead on a
  /// task due at 00:15 fires at 23:45 the previous day; clamping the minute at
  /// zero instead — the obvious shortcut — would fire it at midnight, fifteen
  /// minutes late and on the wrong day.
  ///
  /// ⚠️ With [now], an ALL-DAY task due today whose all-day minute has already
  /// passed fires at the first quarter hour at least [_minLeadMinutes] out
  /// instead. "Remind me to buy milk today" said at 14:00 would otherwise
  /// resolve to 09:00, which the planner skips as past, and the reminder the
  /// user asked for never rings. Timed and past-dated tasks are left alone:
  /// their time is the user's own.
  ///
  /// ⚠️ Not simply the NEXT quarter hour. The time is fixed here, at save,
  /// but only armed by the reminder sweep that runs after the save's
  /// permission prompts; a first-time user on Android's "Alarms & reminders"
  /// page is easily gone a minute. Saved at 14:14 with a 14:15 reminder, the
  /// sweep came back to a time already past, filed it as in flight, and it
  /// never rang. The lead gives the sweep room.
  ///
  /// Still capped at 23:59, so a task captured in the last few minutes of the
  /// day gets less than the lead, and one captured at 23:59 itself resolves to
  /// now and does not ring. Pushing it past midnight would ring it on a day
  /// the task is no longer due, which is worse.
  static LocalDateTime resolveReminderAt(
    TaskDue due, {
    required int allDayReminderMinute,
    int leadMinutes = 0,
    LocalDateTime? now,
  }) {
    final LocalDateTime at = due
        .resolve(allDayMinute: allDayReminderMinute)
        .subtractMinutes(leadMinutes);
    if (now == null || !due.isAllDay || due.date != now.date) return at;
    if (at.isAfter(now)) return at;
    // ceil((now + lead) / 15) * 15. Capped at 23:59 so it still rings on the
    // day the task is due, never at midnight on the next.
    final int next = (now.time.minuteOfDay + _minLeadMinutes + 14) ~/ 15 * 15;
    return LocalDateTime(
      now.date,
      LocalTimeOfDay(next < _minutesPerDay ? next : _minutesPerDay - 1),
    );
  }

  static const int _minutesPerDay = 24 * 60;

  /// How far ahead a moved-forward all-day reminder lands, at the least.
  static const int _minLeadMinutes = 5;
}
