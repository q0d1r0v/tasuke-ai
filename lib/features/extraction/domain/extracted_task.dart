import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

/// One task the extractor found in an utterance.
final class ExtractedTask {
  const ExtractedTask({
    required this.title,
    this.date,
    this.time,
    this.hasReminder = false,
    this.confidence = Confidence.high,
    this.whenText,
  });

  final String title;
  final LocalDate? date;
  final LocalTimeOfDay? time;
  final bool hasReminder;

  /// How sure the pipeline is about [date] and [time].
  final Confidence confidence;

  /// The raw phrase the date came from — "tomorrow at 3 PM". Kept so the
  /// Confirm screen can explain itself and so a failing case can be dropped
  /// straight into the parser's fixture table.
  final String? whenText;

  ExtractedTask copyWith({
    String? title,
    LocalDate? date,
    LocalTimeOfDay? time,
    bool? hasReminder,
    Confidence? confidence,
    bool clearDate = false,
    bool clearTime = false,
  }) => ExtractedTask(
    title: title ?? this.title,
    date: clearDate ? null : (date ?? this.date),
    time: (clearTime || clearDate) ? null : (time ?? this.time),
    hasReminder: hasReminder ?? this.hasReminder,
    confidence: confidence ?? this.confidence,
    whenText: whenText,
  );

  @override
  bool operator ==(Object other) =>
      other is ExtractedTask &&
      other.title == title &&
      other.date == date &&
      other.time == time &&
      other.hasReminder == hasReminder &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(title, date, time, hasReminder, confidence);

  @override
  String toString() =>
      'ExtractedTask("$title", ${date?.toIso() ?? '-'} ${time?.toIso() ?? ''})';
}

enum Confidence {
  /// The deterministic parser matched a phrase it fully understands.
  high,

  /// The parser matched partially, or the date came from the model and only
  /// passed range validation. The Confirm card flags these.
  low,
}
