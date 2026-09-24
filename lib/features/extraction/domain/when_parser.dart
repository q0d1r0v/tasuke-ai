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
    this.dateSpoken = false,
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

  /// Whether the date came from words that name a day ("tomorrow", "Friday",
  /// "the 25th"), as opposed to being implied by a bare time ("at 3" →
  /// today, or tomorrow once 3 has passed).
  ///
  /// The extractor needs the difference: "tomorrow at nine the bank, then at
  /// twelve lunch" means lunch tomorrow, and only a spoken date may be carried
  /// forward like that.
  final bool dateSpoken;

  bool get isEmpty => date == null && time == null;

  /// Whether the moment named is already gone at [now]: a day before today,
  /// or a time earlier today. "Yesterday", and "this morning at 9" said at
  /// 15:00.
  bool isOverAt(LocalDateTime now) {
    final LocalDate? day = date;
    if (day == null) return false;
    final LocalTimeOfDay? at = time;
    return day.isBefore(now.date) ||
        (day == now.date &&
            at != null &&
            at.minuteOfDay < now.time.minuteOfDay);
  }

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
/// one line each — and lets a wrong date be reproduced from the words alone.
final class WhenParser {
  const WhenParser();

  ParsedWhen parse(String phrase, {required LocalDateTime now}) {
    if (phrase.trim().isEmpty) return ParsedWhen.empty;
    final String text = foldTemporalCase(phrase);

    final DateMatch? dateHit = DateGrammar.firstMatch(text, now: now);
    // "…move the appointment from Friday to Monday at 3": the 3 is the new
    // slot's, like the two days. ⚠️ Kept, the call got a reminder today at 15:00.
    final List<(int, int)> moved = DateGrammar.movedRanges(text);
    final List<TimeMatch> timeHits =
        TimeGrammar.allMatches(
          text,
          excludeStart: dateHit?.start ?? -1,
          excludeEnd: dateHit?.end ?? -1,
        )..removeWhere(
          (TimeMatch t) => moved.any(
            ((int, int) r) =>
                t.start >= r.$1 &&
                RegExp(r'^[\s,]*$').hasMatch(
                  text.substring(r.$2, t.start < r.$2 ? r.$2 : t.start),
                ),
          ),
        );
    TimeMatch? timeHit = timeHits.isEmpty ? null : timeHits.first;
    if (dateHit == null && timeHit == null) return ParsedWhen.empty;
    // "In the evening go to the gym at 7", "At 7 go jogging in the morning":
    // the part of the day and its clock time, said apart.
    final TimeMatch? partHit = _partSaidApart(timeHits);
    final TimeMatch? clockHit = partHit == null
        ? null
        : _clockBesides(timeHits, partHit, text);

    // "…in half an hour to take my medicine then tonight at 10": the clock
    // time is said with a day of its own, not with the first one. ⚠️ Paired
    // with the first, it took the place of the half hour's own minute and
    // read as the first day's hour — 10:00, with "tonight" left unread in
    // the title. Said of the same day ("today call Anna tonight at 8") the
    // two are one moment, and the clock's day says which half of it; of
    // another day, or after a moment already exact, they clash, and the
    // first when stands alone — the second stays in the title, where the
    // Confirm card shows it.
    DateMatch? clockDay;
    if (dateHit != null && timeHit != null && partHit == null) {
      final DateMatch? own = _otherDayOf(timeHit, dateHit, text, now);
      if (own != null) {
        if (!dateHit.exact && own.date == dateHit.date) {
          clockDay = own;
        } else {
          timeHit = null;
        }
      }
    }
    // The day that says which half of the day the clock time is: the one it
    // was said with — unless only the first names a part of the day, as in
    // "tomorrow evening … tomorrow at 8".
    final DateMatch? timeDay = clockDay?.impliedMinute != null
        ? clockDay
        : dateHit;

    LocalTimeOfDay? time;
    if (partHit != null && clockHit != null) {
      // ⚠️ Whichever came first used to win alone: "in the evening" was
      // 18:00 with "at 7" left in the title, and "at 7 … in the morning" was
      // right only by luck of the 7.
      final String said = text.substring(clockHit.start, clockHit.end);
      time = _spokenHour(said) == null || _meridiem.hasMatch(said)
          ? clockHit.time
          : TimeGrammar.clockInDayPart(clockHit.time, partHit.dayPart!);
    } else if (timeHit != null) {
      time = _inEveningIfSaid(timeHit, timeDay, text);
    } else if (dateHit?.impliedMinute != null) {
      // "tomorrow morning" carries its own time.
      time = LocalTimeOfDay(dateHit!.impliedMinute!);
    }

    LocalDate? date = dateHit?.date;
    // "tonight at 12", "tonight at 1" — past midnight, so the next calendar
    // day: said at night, noon and one in the afternoon are not meant. An
    // evening rolls over only for midnight itself ("this evening at midnight").
    final int implied = timeDay?.impliedMinute ?? -1;
    if (timeHit != null &&
        clockHit == null &&
        date != null &&
        implied >= ExtractionDefaults.eveningMinute) {
      final LocalTimeOfDay? small = smallHours(
        text.substring(timeHit.start, timeHit.end),
        time!,
        night: implied >= ExtractionDefaults.nightMinute,
      );
      if (small != null) {
        // ⚠️ Said in the small hours, "tonight" is the night already under
        // way: "tonight at 2" at 00:40 is 80 minutes away, not 25 hours. A
        // named day's night ("Friday night") is still the one ahead.
        final bool stillTonight =
            date == now.date &&
            timeDay!.weekday == null &&
            small.minuteOfDay > now.time.minuteOfDay;
        if (!stillTonight) date = date.addDays(1);
        time = small;
      }
    }
    if (date == null && time != null) {
      // A bare time already past today is tomorrow's — but only because no date
      // was given. "today at 3 PM" said at 4 PM stays today and is overdue.
      final bool alreadyPast = time.minuteOfDay < now.time.minuteOfDay;
      date = ExtractionDefaults.bareTimeRollsToTomorrow && alreadyPast
          ? now.date.addDays(1)
          : now.date;
    }

    final List<MatchSpan> spans = _spansOf(<MatchSpan>[
      if (dateHit != null) MatchSpan(dateHit.start, dateHit.end),
      if (clockDay != null) MatchSpan(clockDay.start, clockDay.end),
      if (clockHit != null) ...<MatchSpan>[
        MatchSpan(partHit!.start, partHit.end),
        MatchSpan(clockHit.start, clockHit.end),
      ] else if (timeHit != null)
        MatchSpan(timeHit.start, timeHit.end),
    ]);
    return ParsedWhen(
      date: date,
      time: time,
      confidence: dateHit?.confidence ?? Confidence.high,
      matchStart: spans.first.start,
      matchEnd: spans.last.end,
      spans: spans,
      dateSpoken: dateHit != null,
    );
  }

  /// The day phrase after [day] that [clock] is said with — "tonight" in
  /// "…in half an hour … then tonight at 10", "Friday" in "…on Friday at 3"
  /// — or null when [clock] is said with [day] itself, or with no day.
  static DateMatch? _otherDayOf(
    TimeMatch clock,
    DateMatch day,
    String text,
    LocalDateTime now,
  ) {
    if (_saidTogether(text, day.start, day.end, clock.start, clock.end)) {
      return null;
    }
    DateMatch? best;
    for (final DateMatch other in DateGrammar.allMatches(text, now: now)) {
      if (other.start < day.end) continue;
      if (!_saidTogether(
        text,
        other.start,
        other.end,
        clock.start,
        clock.end,
      )) {
        continue;
      }
      if (best == null || other.length > best.length) best = other;
    }
    return best;
  }

  /// Whether only spaces and commas stand between the two ranges, or they
  /// overlap: one phrase, "tonight at 10", "at 10 tonight", "Friday, at 3".
  static bool _saidTogether(
    String text,
    int aStart,
    int aEnd,
    int bStart,
    int bEnd,
  ) {
    final String between = aEnd <= bStart
        ? text.substring(aEnd, bStart)
        : bEnd <= aStart
        ? text.substring(bEnd, aStart)
        : '';
    return _separators.hasMatch(between);
  }

  static final RegExp _separators = RegExp(r'^[\s,]*$');

  /// "tonight at 8.45", "this evening at 7" — an hour under twelve said with
  /// an evening day is that evening's hour. Without this, "pick up Anna
  /// tonight at 8.45" was a 08:45 reminder, twelve hours early.
  static LocalTimeOfDay _inEveningIfSaid(
    TimeMatch timeHit,
    DateMatch? dateHit,
    String text,
  ) {
    final LocalTimeOfDay time = timeHit.time;
    final int? implied = dateHit?.impliedMinute;
    if (implied == null) return time;
    final String saidText = text.substring(timeHit.start, timeHit.end);
    if (implied == ExtractionDefaults.morningMinute) {
      // "tomorrow morning at 6" — a bare 1–6 is read as the afternoon hour
      // everywhere else, but not with "morning" said: 06:00, not 18:00.
      final int? hour = _spokenHour(saidText);
      if (hour != null &&
          hour >= 1 &&
          hour <= 6 &&
          time.minuteOfDay >= 12 * 60 &&
          !RegExp(r'[ap]\.?\s?m\b').hasMatch(saidText)) {
        return LocalTimeOfDay(time.minuteOfDay - (12 * 60));
      }
      return time;
    }
    if (implied < ExtractionDefaults.eveningMinute) return time;
    if (time.minuteOfDay >= 12 * 60) return time;
    final String said = text.substring(timeHit.start, timeHit.end);
    if (RegExp(r'[ap]\.?\s?m\b').hasMatch(said)) return time;
    // "tonight at midnight" already says which half of the day; adding twelve
    // hours made it noon.
    if (_midnight.hasMatch(said)) return time;
    return LocalTimeOfDay.tryFromMinutes(time.minuteOfDay + (12 * 60)) ?? time;
  }

  static final RegExp _midnight = RegExp(r'\bmidnight\b');

  static final RegExp _meridiem = RegExp(r'[ap]\.?\s?m\b');

  /// The one part of the day among [hits] that says when — "in the evening",
  /// "this morning", "every morning" — when there is exactly one.
  ///
  /// ⚠️ Not a bare "morning": in "good morning call Anna at 5" it is a
  /// greeting, and paired with the 5 it would put the call at 05:00.
  static TimeMatch? _partSaidApart(List<TimeMatch> hits) {
    final List<TimeMatch> parts = <TimeMatch>[
      for (final TimeMatch hit in hits)
        if (hit.dayPart != null && _standsAlone(hit, hits)) hit,
    ];
    if (parts.length != 1) return null;
    final TimeMatch part = parts.single;
    return part.end - part.start > part.dayPart!.length ? part : null;
  }

  /// The first clock time among [hits] that is not part of [part] or of a
  /// longer phrase — ⚠️ "at ten to one in the morning" holds both an "in the
  /// morning" and an "at ten", and pairing those two made it 10:00.
  ///
  /// Null when [part], said after the clock time, belongs to a thing instead
  /// of the task — see [_partOfAThing].
  static TimeMatch? _clockBesides(
    List<TimeMatch> hits,
    TimeMatch part,
    String text,
  ) {
    for (final TimeMatch hit in hits) {
      if (hit.dayPart != null || !_standsAlone(hit, hits)) continue;
      if (_overlap(hit, part)) continue;
      return _partOfAThing(text, hit, part) ? null : hit;
    }
    return null;
  }

  /// Whether [part], said after [clock], tells when a thing named after a
  /// preposition is rather than when the task is: "at 9 buy flowers for the
  /// party in the evening", "at 10 call the hotel about the late check-in in
  /// the evening".
  ///
  /// ⚠️ Paired all the same, the flowers were bought at 21:00 — twelve hours
  /// off — and the party lost its evening from the title. Said straight
  /// after the task's own words ("at 5 go jogging in the morning") the part
  /// of the day is the task's; said first ("in the evening go to the gym at
  /// 7") it is the task's too, whatever the clock time is attached to.
  static bool _partOfAThing(String text, TimeMatch clock, TimeMatch part) =>
      part.start > clock.end &&
      _preposition.hasMatch(text.substring(clock.end, part.start));

  static final RegExp _preposition = RegExp(
    r'\b(?:for|about|to|at|in|with|from|of|before|after|on|into|until|till'
    r'|by|during)\b',
  );

  /// Whether no longer phrase among [hits] covers any of [hit].
  static bool _standsAlone(TimeMatch hit, List<TimeMatch> hits) => !hits.any(
    (TimeMatch other) => other.length > hit.length && _overlap(hit, other),
  );

  static bool _overlap(TimeMatch a, TimeMatch b) =>
      a.start < b.end && b.start < a.end;

  /// The hour after midnight that [said] means when an evening or a night is
  /// being talked about, or null when it means its own clock time.
  ///
  /// [time] is what [said] read as on its own. "midnight" and "a quarter past
  /// midnight" are after midnight under either; a clock time from 12 to 4:59
  /// ("at 2", "ten to one") only under a [night] — "this evening at 1" is not
  /// the small hours.
  static LocalTimeOfDay? smallHours(
    String said,
    LocalTimeOfDay time, {
    required bool night,
  }) {
    final String text = foldTemporalCase(said);
    // "2 pm", "12 noon" already say which half of the day.
    if (RegExp(r'[ap]\.?\s?m\b|\b(?:noon|midday)\b').hasMatch(text)) {
      return null;
    }
    // "midnight", "a quarter past midnight" — but not "ten to midnight".
    final bool midnight = _midnight.hasMatch(text) && time.minuteOfDay < 60;
    final int? hour = midnight
        ? 12
        : night
        ? _spokenHour(text)
        : null;
    // No clock hour said — a part of the day, an evening, a 24-hour "02:00".
    if (hour == null) return null;
    if (midnight) return time;
    // Already read as the small hours ("at 3 in the morning" is 03:00): the
    // extractor's "Tonight" heading passes the time unshifted, and left to
    // the range below it turned evening, 15:00 today.
    if (time.minuteOfDay < 5 * 60) return time;
    // ⚠️ The resolved time, not the spoken hour: "a quarter to one" is 12:45,
    // so 00:45. Built from the hour after "to", every "X to H" came out an
    // hour late, and "a quarter to twelve" moved to 00:45 the next day.
    final int minute = time.minuteOfDay;
    return minute >= 12 * 60 && minute < 17 * 60
        ? LocalTimeOfDay(minute - (12 * 60))
        : null;
  }

  /// The hour as spoken — "6", "6:30", "six" — or null.
  static int? _spokenHour(String said) {
    final Match? digits = RegExp(r'\b(\d{1,2})(?:[:.]\d{2})?\b')
        .firstMatch(said);
    if (digits != null) {
      final String raw = digits[1]!;
      // "06:00" and "18:00" are 24-hour clocks; leave them as said.
      if (raw.length == 2 && (raw.startsWith('0') || int.parse(raw) > 12)) {
        return null;
      }
      return int.parse(raw);
    }
    const List<String> words = <String>[
      'one', 'two', 'three', 'four', 'five', 'six', //
      'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    ];
    for (int i = 0; i < words.length; i++) {
      if (RegExp('\\b${words[i]}\\b').hasMatch(said)) return i + 1;
    }
    return null;
  }

  /// The cut ranges, merged where the date and the time were spoken as one
  /// phrase and kept apart where they were not.
  static List<MatchSpan> _spansOf(List<MatchSpan> found) {
    final List<MatchSpan> sorted = <MatchSpan>[...found]
      ..sort((MatchSpan a, MatchSpan b) => a.start.compareTo(b.start));
    final List<MatchSpan> spans = <MatchSpan>[];
    for (final MatchSpan span in sorted) {
      if (spans.isNotEmpty && span.start <= spans.last.end + 1) {
        final MatchSpan last = spans.removeLast();
        spans.add(
          MatchSpan(last.start, span.end > last.end ? span.end : last.end),
        );
      } else {
        spans.add(span);
      }
    }
    return spans;
  }
}
