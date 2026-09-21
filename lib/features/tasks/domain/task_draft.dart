import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

import 'task.dart';

/// A task that does not exist yet — what the Confirm screen edits and what
/// Save writes.
///
/// It carries a client-side [draftId] so a card can be reordered or dismissed
/// before the drafts have any database identity.
final class TaskDraft {
  const TaskDraft({
    required this.draftId,
    required this.title,
    this.date,
    this.time,
    this.hasReminder = false,
    this.source = TaskSource.voice,
    this.sourceTranscript,
    this.lowConfidenceDate = false,
  });

  final String draftId;
  final String title;
  final LocalDate? date;
  final LocalTimeOfDay? time;
  final bool hasReminder;
  final TaskSource source;
  final String? sourceTranscript;

  /// True when the date came from the model rather than from the deterministic
  /// parser, or when the parser matched with low confidence. The Confirm card
  /// flags these so the user's eye goes to the one that might be wrong.
  final bool lowConfidenceDate;

  bool get isValid => TaskTitle.isValid(title);

  bool get isAllDay => time == null;

  TaskDraft copyWith({
    String? title,
    LocalDate? date,
    LocalTimeOfDay? time,
    bool? hasReminder,
    bool? lowConfidenceDate,
    bool clearDate = false,
    bool clearTime = false,
  }) => TaskDraft(
    draftId: draftId,
    title: title ?? this.title,
    date: clearDate ? null : (date ?? this.date),
    time: (clearTime || clearDate) ? null : (time ?? this.time),
    hasReminder: hasReminder ?? this.hasReminder,
    source: source,
    sourceTranscript: sourceTranscript,
    lowConfidenceDate: lowConfidenceDate ?? this.lowConfidenceDate,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskDraft &&
      other.draftId == draftId &&
      other.title == title &&
      other.date == date &&
      other.time == time &&
      other.hasReminder == hasReminder &&
      other.source == source &&
      other.sourceTranscript == sourceTranscript &&
      other.lowConfidenceDate == lowConfidenceDate;

  @override
  int get hashCode => Object.hash(
    draftId,
    title,
    date,
    time,
    hasReminder,
    source,
    sourceTranscript,
    lowConfidenceDate,
  );

  @override
  String toString() => 'TaskDraft("$title", ${date?.toIso() ?? 'someday'})';
}
