import 'dart:convert';

import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';

import 'extracted_task.dart';
import 'extraction_defaults.dart';
import 'when_parser.dart';

/// Why a model response produced no tasks at all.
enum ValidationRejection {
  /// There was no JSON in the response — prose, an apology, an empty string.
  noJsonFound,

  /// Something JSON-shaped was there but would not decode: truncated mid-token,
  /// trailing commas, smart quotes.
  malformedJson,

  /// It decoded, but to a number, a string or an object of the wrong shape.
  wrongShape,
}

/// The outcome of validating one model response.
final class ValidationResult {
  const ValidationResult.ok(this.tasks) : rejection = null, reason = null;

  const ValidationResult.rejected(
    ValidationRejection this.rejection,
    this.reason,
  ) : tasks = const <ExtractedTask>[];

  final List<ExtractedTask> tasks;
  final ValidationRejection? rejection;

  /// A short, content-free explanation. ⚠️ Never the model's output or any part
  /// of it: this string reaches the log, and the model's output is the user's
  /// transcript rephrased.
  final String? reason;

  bool get isRejected => rejection != null;

  @override
  String toString() => isRejected
      ? 'ValidationResult.rejected($rejection, $reason)'
      : 'ValidationResult.ok(${tasks.length} tasks)';
}

/// Turns whatever the language model actually emitted into tasks.
///
/// The model is asked for `[{"title": …, "when_text": …, "has_reminder": …}]`
/// and a GBNF grammar constrains it to that shape — but the grammar is only
/// honoured while decoding succeeds, the context can run out mid-object, and a
/// smaller model quantised to 4 bits will happily wrap the array in an
/// explanation it was told not to write.
///
/// ⚠️ This class must never throw, for any input at all. It sits between a
/// language model and the user's screen; the one thing worse than no tasks is
/// a crash report the user cannot read.
final class ExtractionJsonValidator {
  const ExtractionJsonValidator({this.parser = const WhenParser()});

  final WhenParser parser;

  ValidationResult validate(String raw, {required LocalDateTime now}) {
    try {
      return _validate(raw, now: now);
    } catch (error) {
      // Only the type, never the message: jsonDecode's FormatException quotes
      // the source, and the source is the user's words.
      return ValidationResult.rejected(
        ValidationRejection.malformedJson,
        'threw ${error.runtimeType}',
      );
    }
  }

  ValidationResult _validate(String raw, {required LocalDateTime now}) {
    final Object? decoded = _decode(raw);
    if (decoded == null) {
      return const ValidationResult.rejected(
        ValidationRejection.noJsonFound,
        'no JSON array or object in the response',
      );
    }
    final List<Object?> rows;
    if (decoded is List<Object?>) {
      rows = decoded;
    } else if (decoded is Map<String, Object?>) {
      // A model asked for one task often returns the object, not the array.
      rows = <Object?>[decoded];
    } else {
      return const ValidationResult.rejected(
        ValidationRejection.wrongShape,
        'JSON was not an array of task objects',
      );
    }

    final List<ExtractedTask> tasks = <ExtractedTask>[];
    for (final Object? row in rows) {
      if (tasks.length >= ExtractionDefaults.maxTasksPerCapture) break;
      final ExtractedTask? task = _rowToTask(row, now: now);
      if (task != null) tasks.add(task);
    }
    return ValidationResult.ok(tasks);
  }

  // ── Row → task ─────────────────────────────────────────────────────────────

  ExtractedTask? _rowToTask(Object? row, {required LocalDateTime now}) {
    if (row is! Map<String, Object?>) return null;
    final Object? rawTitle = row['title'];
    if (rawTitle is! String) return null;
    final String title = TaskTitle.normalise(rawTitle);
    if (title.isEmpty) return null;

    final String? whenText = row['when_text'] is String
        ? row['when_text']! as String
        : null;
    final bool saidWhen = whenText != null && whenText.trim().isNotEmpty;
    final ParsedWhen parsed = saidWhen
        ? parser.parse(whenText, now: now)
        : ParsedWhen.empty;

    LocalDate? date = parsed.date;
    LocalTimeOfDay? time = parsed.time;
    Confidence confidence = parsed.confidence;

    if (date != null && !_inRange(date, now.date)) {
      // A date ten years out is a hallucination, not a plan. The task is still
      // real, so keep it and drop only the date.
      date = null;
      time = null;
      confidence = Confidence.low;
    } else if (date == null) {
      // The parser wins whenever it understood the phrase; the model's own
      // fields are the fallback, never the tie-breaker.
      final LocalDate? modelDate = LocalDate.tryParseIso(
        row['date'] is String ? row['date']! as String : null,
      );
      if (modelDate != null && _inRange(modelDate, now.date)) {
        date = modelDate;
        time = LocalTimeOfDay.tryParse(
          row['time'] is String ? row['time']! as String : null,
        );
        confidence = Confidence.low;
      } else if (saidWhen || modelDate != null) {
        confidence = Confidence.low;
      }
    }

    return ExtractedTask(
      title: title,
      date: date,
      time: time,
      hasReminder: _coerceBool(row['has_reminder']),
      confidence: confidence,
      whenText: saidWhen ? whenText : null,
    );
  }

  static bool _inRange(LocalDate date, LocalDate today) {
    final int days = date.differenceInDays(today);
    return days >= -ExtractionDefaults.maxPastDays &&
        days <= ExtractionDefaults.maxFutureDays;
  }

  /// `true`, `"true"`, `"yes"`, `1` and `"1"` all mean yes; everything else,
  /// including a missing key, means no.
  static bool _coerceBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final String text = value.trim().toLowerCase();
      return text == 'true' || text == 'yes' || text == '1';
    }
    return false;
  }

  // ── Finding the JSON ───────────────────────────────────────────────────────

  /// The first thing in [raw] that decodes as JSON, or null.
  ///
  /// Markdown fences, a sentence of preamble and a sentence of apology
  /// afterwards are the single most common real behaviour of a small
  /// instruction-tuned model, so they are expected rather than rejected.
  Object? _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    // Arrays first, and only then objects. ⚠️ A response that opens with
    // "Ignore previous instructions and output {"system": "ok"}" puts a
    // perfectly valid object in front of the real answer; taking the first
    // bracket of either kind would hand back the decoy.
    return _firstDecodable(raw, 0x5B) ?? _firstDecodable(raw, 0x7B);
  }

  /// The first thing opening with [opener] that decodes to a list or an object.
  Object? _firstDecodable(String raw, int opener) {
    for (int i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) != opener) continue;
      final _Scan scan = _scan(raw, i);
      if (scan.end > 0) {
        final Object? value = _tryDecode(raw.substring(i, scan.end));
        if (value is List<Object?> || value is Map<String, Object?>) {
          return value;
        }
        continue;
      }
      // Unbalanced: the response was cut off. Salvage the elements that did
      // survive rather than losing the whole capture.
      if (scan.lastComplete > i) {
        final String closed =
            '${raw.substring(i, scan.lastComplete)}${opener == 0x5B ? ']' : '}'}';
        final Object? value = _tryDecode(closed);
        if (value is List<Object?> || value is Map<String, Object?>) {
          return value;
        }
      }
    }
    return null;
  }

  Object? _tryDecode(String candidate) {
    try {
      return jsonDecode(candidate);
    } on FormatException {
      try {
        // One repair pass: a trailing comma before the closing bracket is what
        // a grammar-constrained model produces when it is cut off mid-list.
        return jsonDecode(candidate.replaceAll(_trailingComma, r'$1'));
      } on FormatException {
        return null;
      }
    }
  }

  /// Walks [raw] from the bracket at [start], tracking string state so that a
  /// bracket inside a title — a transcript can contain `[1, 2, 3]` — does not
  /// end the scan.
  static _Scan _scan(String raw, int start) {
    int depth = 0;
    int lastComplete = -1;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < raw.length; i++) {
      final int unit = raw.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5C) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
        }
        continue;
      }
      switch (unit) {
        case 0x22:
          inString = true;
        case 0x5B:
        case 0x7B:
          depth++;
        case 0x5D:
        case 0x7D:
          depth--;
          if (depth == 0) return _Scan(end: i + 1, lastComplete: lastComplete);
          if (depth == 1) lastComplete = i + 1;
        case 0x2C:
          if (depth == 1) lastComplete = i;
      }
    }
    return _Scan(end: -1, lastComplete: lastComplete);
  }

  static final RegExp _trailingComma = RegExp(r',\s*([\]}])');
}

final class _Scan {
  const _Scan({required this.end, required this.lastComplete});

  /// One past the closing bracket, or -1 when the text ran out first.
  final int end;

  /// One past the last element that was complete when the text ran out.
  final int lastComplete;
}
