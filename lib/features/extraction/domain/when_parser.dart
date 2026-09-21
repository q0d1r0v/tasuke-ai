import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

import 'date_grammar.dart';
import 'extracted_task.dart';
import 'extraction_defaults.dart';
import 'time_grammar.dart';

/// A half-open character range of the phrase that was parsed.
final class MatchSpan {
  const MatchSpan(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => end <= start;

  @override
  bool operator ==(Object other) =>
      other is MatchSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}

/// What a phrase said about when something is due.
final class ParsedWhen {
  const ParsedWhen({
    this.date,
    this.time,
    this.confidence = Confidence.high,
    this.matchStart = 0,
    this.matchEnd = 0,
    this.spans = const <MatchSpan>[],
  });

  /// Nothing temporal was said. Its span is empty, so the title cleaner cuts
  /// nothing — "call Mark" must come back out of the parser whole.
  static const ParsedWhen empty = ParsedWhen();

  final LocalDate? date;
  final LocalTimeOfDay? time;
  final Confidence confidence;

  /// The character range of the phrase that produced the match, so the title
  /// cleaner can cut exactly that span out.
  final int matchStart;
  final int matchEnd;

  /// The individual ranges that [matchStart]..[matchEnd] spans.
  ///
  /// Usually one, because the date and the time were spoken together. In
  /// "Friday check the App Store at 3 PM" they are two, with the whole title
  /// between them — cutting the outer range there would leave nothing.
  final List<MatchSpan> spans;

  bool get isEmpty => date == null && time == null;

  @override
  bool operator ==(Object other) =>
      other is ParsedWhen &&
      other.date == date &&
      other.time == time &&
      other.confidence == confidence &&
      other.matchStart == matchStart &&
      other.matchEnd == matchEnd;

  @override
  int get hashCode => Object.hash(date, time, confidence, matchStart, matchEnd);

  @override
  String toString() =>
      'ParsedWhen(${date?.toIso() ?? '-'} ${time?.toIso() ?? ''} '
      '$confidence $matchStart..$matchEnd)';
}

/// Turns "tomorrow at 3 PM" into a date and a time.
///
/// Deterministic and pure: the same phrase and the same `now` always give the
/// same answer, which is what lets the corpus hold a hundred and fifty cases as
/// one line each. The language model is never asked to do date arithmetic —
/// it is asked for the words, and this does the arithmetic.
final class WhenParser {
  const WhenParser();

  ParsedWhen parse(String phrase, {required LocalDateTime now}) {
    if (phrase.trim().isEmpty) return ParsedWhen.empty;
    final String text = foldTemporalCase(phrase);

    final DateMatch? dateHit = DateGrammar.firstMatch(text, now: now);
    final TimeMatch? timeHit = TimeGrammar.firstMatch(
      text,
      excludeStart: dateHit?.start ?? -1,
      excludeEnd: dateHit?.end ?? -1,
    );
    if (dateHit == null && timeHit == null) return ParsedWhen.empty;

    LocalTimeOfDay? time;
    if (timeHit != null) {
      time = timeHit.time;
    } else if (dateHit?.impliedMinute != null) {
      // "tomorrow morning" carries its own time.
      time = LocalTimeOfDay(dateHit!.impliedMinute!);
    }

    LocalDate? date = dateHit?.date;
    if (date == null && time != null) {
      // A bare time already past today is tomorrow's — but only because no date
      // was given. "today at 3 PM" said at 4 PM stays today and is overdue.
      final bool alreadyPast = time.minuteOfDay < now.time.minuteOfDay;
      date = ExtractionDefaults.bareTimeRollsToTomorrow && alreadyPast
          ? now.date.addDays(1)
          : now.date;
    }

    final List<MatchSpan> spans = _spansOf(dateHit, timeHit);
    return ParsedWhen(
      date: date,
      time: time,
      confidence: dateHit?.confidence ?? Confidence.high,
      matchStart: spans.first.start,
      matchEnd: spans.last.end,
      spans: spans,
    );
  }

  /// The cut ranges, merged when the date and the time were spoken as one
  /// phrase and kept apart when they were not.
  static List<MatchSpan> _spansOf(DateMatch? date, TimeMatch? time) {
    final List<MatchSpan> spans = <MatchSpan>[
      if (date != null) MatchSpan(date.start, date.end),
      if (time != null) MatchSpan(time.start, time.end),
    ]..sort((MatchSpan a, MatchSpan b) => a.start.compareTo(b.start));
    if (spans.length == 2 && spans[1].start <= spans[0].end + 1) {
      return <MatchSpan>[MatchSpan(spans[0].start, spans[1].end)];
    }
    return spans;
  }
}
