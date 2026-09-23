import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

/// Where a task came from. Drives the Stats breakdown and nothing else in v1,
/// but it is the column you wish you had the first time someone asks whether
/// voice capture is actually being used.
enum TaskSource {
  voice,
  manual;

  static TaskSource fromName(String? name) => TaskSource.values.firstWhere(
    (TaskSource s) => s.name == name,
    orElse: () => TaskSource.manual,
  );
}

/// When a task is due, on the user's own calendar.
///
/// [time] null means "all day". That is a genuinely different thing from a
/// task with no due date at all, which is modelled as a null [TaskDue].
final class TaskDue {
  const TaskDue({required this.date, this.time});

  final LocalDate date;
  final LocalTimeOfDay? time;

  bool get isAllDay => time == null;

  /// The civil instant this task is due at, using [allDayMinute] when the task
  /// has no time of its own.
  LocalDateTime resolve({required int allDayMinute}) =>
      LocalDateTime(date, time ?? LocalTimeOfDay(allDayMinute));

  TaskDue copyWith({
    LocalDate? date,
    LocalTimeOfDay? time,
    bool clearTime = false,
  }) => TaskDue(
    date: date ?? this.date,
    time: clearTime ? null : (time ?? this.time),
  );

  @override
  bool operator ==(Object other) =>
      other is TaskDue && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() =>
      'TaskDue(${date.toIso()}, ${time?.toIso() ?? 'all-day'})';
}

/// A task's reminder.
///
/// [at] is a **civil** date-time — a wall-clock appointment, not an instant.
/// The absolute moment is computed at scheduling time against the device's
/// current zone, which is what keeps "tomorrow at 3 PM" firing at 3 PM after a
/// flight and on both sides of a daylight-saving transition.
final class TaskReminder {
  const TaskReminder({
    this.enabled = false,
    this.leadMinutes = 0,
    this.at,
    this.notificationId,
  });

  static const TaskReminder none = TaskReminder();

  final bool enabled;

  /// How many minutes before the due time the reminder fires. 0 = at the time.
  final int leadMinutes;

  /// The resolved civil instant. Null when the task has no due date.
  final LocalDateTime? at;

  /// A stable id, so editing a task targets the same OS alarm slot.
  final int? notificationId;

  /// Whether this reminder should actually be handed to the OS.
  bool get isSchedulable => enabled && at != null;

  TaskReminder copyWith({
    bool? enabled,
    int? leadMinutes,
    LocalDateTime? at,
    int? notificationId,
    bool clearAt = false,
  }) => TaskReminder(
    enabled: enabled ?? this.enabled,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    at: clearAt ? null : (at ?? this.at),
    notificationId: notificationId ?? this.notificationId,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes &&
      other.at == at &&
      other.notificationId == notificationId;

  @override
  int get hashCode => Object.hash(enabled, leadMinutes, at, notificationId);
}

/// A saved task.
///
/// Pure Dart: no Flutter, no Drift. `TaskMapper` is the single place where a
/// database row becomes one of these.
final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.due,
    this.reminder = TaskReminder.none,
    this.completed = false,
    this.completedAt,
    this.source = TaskSource.manual,
    this.sourceTranscript,
    this.captureId,
    this.sortOrder = 0,
  });

  /// The longest title the UI lays out without becoming a paragraph. Enforced
  /// by [TaskTitle.normalise] rather than by an assert, because the input is
  /// whatever was made of a transcript, and a throw there is a crash the user
  /// caused by speaking.
  static const int maxTitleLength = 200;

  final String id;
  final String title;
  final String? notes;
  final TaskDue? due;
  final TaskReminder reminder;
  final bool completed;

  /// UTC instants — these answer "when did this happen".
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final TaskSource source;

  /// What the user actually said. Local only, never logged, never transmitted.
  final String? sourceTranscript;

  /// Groups the tasks produced by one utterance, so Confirm's "discard all"
  /// and a future undo can act on the batch.
  final String? captureId;

  final int sortOrder;

  bool get hasDate => due != null;

  bool get isAllDay => due?.isAllDay ?? true;

  /// Overdue is a question about the user's calendar, so it is answered with a
  /// [LocalDate] and never by comparing UTC instants.
  bool isOverdue(LocalDate today) =>
      !completed && due != null && due!.date.isBefore(today);

  bool isDueOn(LocalDate day) => due?.date == day;

  Task copyWith({
    String? title,
    String? notes,
    TaskDue? due,
    TaskReminder? reminder,
    bool? completed,
    DateTime? completedAt,
    DateTime? updatedAt,
    TaskSource? source,
    String? sourceTranscript,
    String? captureId,
    int? sortOrder,
    bool clearDue = false,
    bool clearNotes = false,
    bool clearCompletedAt = false,
  }) => Task(
    id: id,
    title: title ?? this.title,
    notes: clearNotes ? null : (notes ?? this.notes),
    due: clearDue ? null : (due ?? this.due),
    reminder: reminder ?? this.reminder,
    completed: completed ?? this.completed,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source ?? this.source,
    sourceTranscript: sourceTranscript ?? this.sourceTranscript,
    captureId: captureId ?? this.captureId,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.notes == notes &&
      other.due == due &&
      other.reminder == reminder &&
      other.completed == completed &&
      other.completedAt == completedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.source == source &&
      other.sourceTranscript == sourceTranscript &&
      other.captureId == captureId &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    due,
    reminder,
    completed,
    completedAt,
    createdAt,
    updatedAt,
    source,
    sourceTranscript,
    captureId,
    sortOrder,
  );

  @override
  String toString() => 'Task($id, "$title", ${due ?? 'someday'})';
}

/// Title normalisation, in one place because three callers need identical
/// behaviour: the extractor, the Confirm editor and the Task Details editor.
abstract final class TaskTitle {
  /// Collapses whitespace, trims, and truncates on a **grapheme** boundary.
  ///
  /// Truncating by code unit splits surrogate pairs and ZWJ emoji sequences,
  /// which renders as a replacement character rather than as a shorter title.
  static String normalise(String raw) {
    final String collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= Task.maxTitleLength) return collapsed;
    final List<int> runes = collapsed.runes.toList();
    final StringBuffer out = StringBuffer();
    for (final int rune in runes) {
      final String next = String.fromCharCode(rune);
      if (out.length + next.length > Task.maxTitleLength) break;
      out.write(next);
    }
    return out.toString().trimRight();
  }

  static bool isValid(String raw) => normalise(raw).isNotEmpty;
}
