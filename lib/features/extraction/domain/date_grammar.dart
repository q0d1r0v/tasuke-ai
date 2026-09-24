import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

import 'clause_splitter.dart';
import 'extracted_task.dart';
import 'extraction_defaults.dart';
import 'time_grammar.dart';

/// One calendar-date phrase, with the span of the utterance that produced it.
final class DateMatch {
  const DateMatch({
    required this.date,
    required this.start,
    required this.end,
    this.impliedMinute,
    this.confidence = Confidence.high,
    this.namesMonth = false,
    this.weekday,
    this.dayOfMonth,
    this.exact = false,
  });

  final LocalDate date;
  final int start;
  final int end;

  /// The time the date phrase carried with it — "tomorrow morning" is 09:00,
  /// "in two hours" is an exact clock time. Null when the phrase said nothing
  /// about the time of day.
  final int? impliedMinute;

  final Confidence confidence;

  /// Whether the phrase pinned down a day of a named month — "5 December",
  /// "12/5", "2026-12-05" — the most specific thing a date phrase can say.
  final bool namesMonth;

  /// The weekday the phrase named ("Thursday", "next Friday"), if it named one.
  final int? weekday;

  /// The day of the month a phrase gave without its month ("the 5th", "on the
  /// fifth"). [date] is only the next such day; a weekday said with it can
  /// say which month is meant.
  final int? dayOfMonth;

  /// Whether the phrase names a moment to the minute — "in half an hour", "in
  /// two hours" — so that no clock time said elsewhere can be its time.
  final bool exact;

  int get length => end - start;

  @override
  String toString() => 'DateMatch(${date.toIso()}, $start..$end)';
}

typedef _DateResolver = DateMatch? Function(
  RegExpMatch match,
  LocalDateTime now,
  String text,
);

final class _DateRule {
  const _DateRule(this.pattern, this.resolve);

  final RegExp pattern;
  final _DateResolver resolve;
}

/// Every calendar-date phrase the app understands.
abstract final class DateGrammar {
  /// Every valid date phrase in [phrase], best first — leftmost, then longest,
  /// so "the day after tomorrow" wins over the "tomorrow" inside it and "next
  /// Friday" over the "Friday".
  static List<DateMatch> allMatches(
    String phrase, {
    required LocalDateTime now,
  }) {
    final String text = foldTemporalCase(phrase);
    final List<DateMatch> found = <DateMatch>[];
    for (final _DateRule rule in _rules) {
      for (final RegExpMatch match in rule.pattern.allMatches(text)) {
        final DateMatch? hit = rule.resolve(match, now, text);
        if (hit != null) found.add(hit);
      }
    }
    found.sort((DateMatch a, DateMatch b) {
      final int byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.length.compareTo(a.length);
    });
    final List<(int, int)> moved = _movedRanges(found, text);
    found.removeWhere(
      (DateMatch m) =>
          moved.any(((int, int) r) => m.start >= r.$1 && m.start <= r.$2),
    );
    return found;
  }

  /// Where [phrase] says "move the appointment from Friday to Monday": from
  /// the old day to the end of the new one. Both days, and a time said right
  /// after the new one ("…to Monday at 3"), belong to the thing moved, not to
  /// the task. ⚠️ Read as a when, the call took the old day, and the title
  /// lost it: "Call the dentist to move the appointment from to Monday".
  static List<(int, int)> movedRanges(String phrase) {
    final String text = foldTemporalCase(phrase);
    final List<DateMatch> found = <DateMatch>[];
    for (final _DateRule rule in _rules) {
      for (final RegExpMatch match in rule.pattern.allMatches(text)) {
        final DateMatch? hit = rule.resolve(match, _anyMoment, text);
        if (hit != null) found.add(hit);
      }
    }
    return _movedRanges(found, text);
  }

  static List<(int, int)> _movedRanges(List<DateMatch> found, String text) {
    final List<(int, int)> ranges = <(int, int)>[];
    for (final RegExpMatch move in _moveFrom.allMatches(text)) {
      final int from = move.end;
      final DateMatch? old = found
          .where((DateMatch m) => m.start == from)
          .firstOrNull;
      if (old == null) continue;
      final Match? to = _to.matchAsPrefix(text, old.end);
      if (to == null) continue;
      final int onward = to.end;
      int end = -1;
      for (final DateMatch m in found) {
        if (m.start == onward && m.end > end) end = m.end;
      }
      if (end >= 0) ranges.add((from, end));
    }
    return ranges;
  }

  static final RegExp _moveFrom = RegExp(
    r'\b(?:move|moving|moved|reschedule|rescheduling|change|changing|shift'
    r'|push|postpone)\b[^.,;!?]{0,60}?\bfrom\s+',
  );

  /// ⚠️ "to" only: "change the bandage from today until Sunday at 8 am" is
  /// how long, not where to, and lost its 08:00.
  static final RegExp _to = RegExp(r'\s+to\s+');

  /// The date [phrase] is about: the best of [allMatches], unless a date that
  /// names its month, or a day of the month after a weekday, is part of the
  /// same phrase.
  ///
  /// ⚠️ Leftmost-wins alone let the vaguer reading take the phrase. "on the
  /// 5th of December" also reads "on the 5th", which starts one word earlier,
  /// and "Thursday, October 15th" starts with a weekday — so the reminder
  /// landed on the next 5th, or on tomorrow, with the month left in the title.
  /// The merged match spans the whole phrase so none of it stays behind.
  static DateMatch? firstMatch(String phrase, {required LocalDateTime now}) {
    final String text = foldTemporalCase(phrase);
    final List<DateMatch> all = allMatches(text, now: now);
    if (all.isEmpty) return null;
    final DateMatch first = all.first;
    if (first.namesMonth) return first;
    for (final DateMatch named in all.skip(1)) {
      if (!named.namesMonth) continue;
      final bool overlaps = named.start < first.end;
      final bool followsWeekday =
          first.weekday != null &&
          !overlaps &&
          _onlySeparators(text, first, named);
      if (!overlaps && !followsWeekday) continue;
      final bool clash =
          first.weekday != null && first.weekday != named.date.weekday;
      return DateMatch(
        date: named.date,
        start: first.start,
        end: named.end > first.end ? named.end : first.end,
        impliedMinute: first.impliedMinute ?? named.impliedMinute,
        // "Thursday, October 16th" when the 16th is a Friday: one of the two
        // is wrong. Keep the date, and let the Confirm card ask.
        confidence: clash ? Confidence.low : named.confidence,
        namesMonth: true,
        weekday: first.weekday,
      );
    }
    // ⚠️ "Monday the 5th", "Thursday the 1st" name no month, and the weekday
    // alone used to win: the coming Monday, one to three weeks early, with
    // "the 5th" left in the title. Together they say which 5th is meant.
    // Not after "last Monday": the day of the month only ever looks ahead.
    if (first.weekday != null && !first.date.isBefore(now.date)) {
      for (final DateMatch day in all.skip(1)) {
        if (day.dayOfMonth == null) continue;
        if (day.start >= first.end && !_onlySeparators(text, first, day)) {
          continue;
        }
        final LocalDate? agreed = _dayOnWeekday(
          day.date,
          day.dayOfMonth!,
          first.weekday!,
        );
        return DateMatch(
          date: agreed ?? day.date,
          start: first.start,
          end: day.end > first.end ? day.end : first.end,
          impliedMinute: first.impliedMinute ?? day.impliedMinute,
          // "Tuesday the 5th" when no 5th soon is a Tuesday: as with a named
          // month, keep the date and let the Confirm card ask.
          confidence: agreed == null ? Confidence.low : day.confidence,
          weekday: first.weekday,
          dayOfMonth: day.dayOfMonth,
        );
      }
    }
    return first;
  }

  /// Where the date phrases in [phrase] are, for a caller that needs to know
  /// where a when is but not which day it names — the clause splitter, which
  /// has no `now`.
  ///
  /// ⚠️ Resolved against a fixed moment, so only the offsets mean anything.
  /// No rule's span depends on the day it is resolved on; only its date does.
  static List<(int, int)> spans(String phrase) => <(int, int)>[
    for (final DateMatch m in allMatches(phrase, now: _anyMoment))
      (m.start, m.end),
  ];

  static const LocalDateTime _anyMoment = LocalDateTime(
    LocalDate(2026, 1, 1),
    LocalTimeOfDay(12 * 60),
  );

  /// Whether only spaces and commas stand between [a] and [b], so they are one
  /// phrase: "Thursday, October 15th", not "Friday and December 5".
  static bool _onlySeparators(String text, DateMatch a, DateMatch b) =>
      RegExp(r'^[\s,]*$').hasMatch(text.substring(a.end, b.start));

  /// The first of the next two [day]-of-the-months, from [next] on, that falls
  /// on [weekday]; null when neither does.
  ///
  /// ⚠️ Two, not "until one fits": every day up to the 28th falls on every
  /// weekday within a year, so an unbounded search turned a slip of the tongue
  /// ("Tuesday the 5th" meaning Monday's) into a confident date months away.
  static LocalDate? _dayOnWeekday(LocalDate next, int day, int weekday) {
    if (next.weekday == weekday) return next;
    final LocalDate? after = dayOfMonthOnOrAfter(
      LocalDate(next.year, next.month, 1).addMonths(1),
      day,
    );
    return after != null && after.weekday == weekday ? after : null;
  }

  // ── Calendar arithmetic ────────────────────────────────────────────────────

  /// The next [target] weekday. With [allowToday] false — which is what
  /// [ExtractionDefaults.bareWeekdayIsStrictlyForward] asks for — "Friday" said
  /// on a Friday is a week away.
  static LocalDate forwardWeekday(
    LocalDate today,
    int target, {
    required bool allowToday,
  }) {
    final int delta = (target - today.weekday) % 7;
    if (delta == 0) return allowToday ? today : today.addDays(7);
    return today.addDays(delta);
  }

  /// The [target] weekday of the following calendar week, counting weeks from
  /// Monday. "Next Friday" is never today and never this week's Friday.
  static LocalDate nextWeekWeekday(LocalDate today, int target) =>
      today.addDays(8 - today.weekday).addDays(target - 1);

  static LocalDate lastWeekday(LocalDate today, int target) {
    final int delta = (today.weekday - target) % 7;
    return today.addDays(-(delta == 0 ? 7 : delta));
  }

  /// The next day-of-month [day] on or after [today], skipping months that do
  /// not have that day — "the 31st" in February is 31 March.
  static LocalDate? dayOfMonthOnOrAfter(LocalDate today, int day) {
    if (day < 1 || day > 31) return null;
    final LocalDate firstOfThisMonth = LocalDate(today.year, today.month, 1);
    for (int i = 0; i < 24; i++) {
      final LocalDate month = firstOfThisMonth.addMonths(i);
      if (day > LocalDate.daysInMonth(month.year, month.month)) continue;
      final LocalDate candidate = LocalDate(month.year, month.month, day);
      if (!candidate.isBefore(today)) return candidate;
    }
    return null;
  }

  static LocalDate? _exactDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1) return null;
    if (day > LocalDate.daysInMonth(year, month)) return null;
    return LocalDate(year, month, day);
  }

  /// A month/day with no year. Rolls forward a year when the date has already
  /// gone past, per [ExtractionDefaults.bareDateRollsToNextYear], and keeps
  /// rolling past the years where the date does not exist at all (29 February).
  static LocalDate? _yearlessDate(LocalDate today, int month, int day) {
    if (!ExtractionDefaults.bareDateRollsToNextYear) {
      return _exactDate(today.year, month, day);
    }
    for (int year = today.year; year <= today.year + 8; year++) {
      final LocalDate? candidate = _exactDate(year, month, day);
      if (candidate != null && !candidate.isBefore(today)) return candidate;
    }
    return null;
  }

  // ── Ambiguity guard ────────────────────────────────────────────────────────

  /// Whether the day or month word at [start]..[end] is being used as a date.
  ///
  /// ⚠️ This is what keeps "march to the store", "may I call him", "Sun is out"
  /// and "I sat on the bench" out of the calendar. Every one of them is a real
  /// transcript, and every one of them contains a perfectly good month or day
  /// name. The word only counts when something around it is date-shaped: a
  /// preposition in front, a day number either side, a part of the day behind
  /// it, or sentence-initial position followed by a verb ("Friday check the
  /// App Store").
  static bool _hasDateContext(String text, int start, int end) {
    final String before = wordBefore(text, start);
    final String after = wordAfter(text, end);
    if (_isDayNumber(after) || TimeGrammar.dayPartMinute(after) != null) {
      return true;
    }
    // Sentence-initial: "Friday check the App Store" is a day, "Sun is out" is
    // not, and the difference is entirely the word behind it.
    if (before.isEmpty) return ClauseLexicon.isImperativeVerb(after);
    return _dateIshPrefixes.contains(before) || _isDayNumber(before);
  }

  static bool _isDayNumber(String word) {
    final int? value = int.tryParse(word.replaceAll(_ordinalSuffix, ''));
    return value != null && value >= 1 && value <= 31;
  }

  /// Where inside [match] the bare word [word] sits. Every pattern that needs
  /// this has the word exactly once, and Dart's [RegExpMatch] does not expose
  /// per-group offsets.
  static int _offsetOf(RegExpMatch match, String word) =>
      match.start + match[0]!.indexOf(word);

  // ── Resolvers ──────────────────────────────────────────────────────────────

  static DateMatch _relative(
    RegExpMatch match,
    LocalDateTime now,
    int days,
    String? dayPart,
  ) => DateMatch(
    date: now.date.addDays(days),
    start: match.start,
    end: match.end,
    impliedMinute: dayPart == null ? null : TimeGrammar.dayPartMinute(dayPart),
  );

  static DateMatch? _tomorrow(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, 1, m[1]);

  static DateMatch? _today(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, 0, m[1]);

  static DateMatch? _yesterday(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, -1, m[1]);

  static DateMatch? _dayAfterTomorrow(
    RegExpMatch m,
    LocalDateTime now,
    String t,
  ) => _relative(m, now, 2, null);

  static DateMatch? _dayBeforeYesterday(
    RegExpMatch m,
    LocalDateTime now,
    String t,
  ) => _relative(m, now, -2, null);

  static DateMatch? _tonight(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, 0, 'night');

  static DateMatch? _lastNight(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, -1, 'night');

  static DateMatch? _thisDayPart(RegExpMatch m, LocalDateTime now, String t) =>
      _relative(m, now, 0, m[1]);

  static DateMatch? _weekday(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final String? prefix = match[1];
    final String word = match[2]!;
    final int target = _weekdays[word]!;
    if (prefix == null && _ambiguousWords.contains(word)) {
      final int start = _offsetOf(match, word);
      if (!_hasDateContext(text, start, start + word.length)) return null;
    }
    final LocalDate today = now.date;
    final LocalDate date = switch (prefix) {
      'next' => nextWeekWeekday(today, target),
      'last' || 'past' => lastWeekday(today, target),
      // "this Friday" is the Friday you are standing in; a bare "Friday" is the
      // one coming up.
      'this' ||
      'this coming' => forwardWeekday(today, target, allowToday: true),
      _ => forwardWeekday(
        today,
        target,
        allowToday: !ExtractionDefaults.bareWeekdayIsStrictlyForward,
      ),
    };
    return DateMatch(
      date: date,
      start: match.start,
      end: match.end,
      impliedMinute: match[3] == null
          ? null
          : TimeGrammar.dayPartMinute(match[3]!),
      weekday: target,
    );
  }

  /// "next week on Tuesday", "Tuesday next week" — the weekday of the
  /// following calendar week, like "next Tuesday".
  ///
  /// ⚠️ Without it "next week" matched on its own, leftmost: the Monday of next
  /// week, with "on Tuesday" left in the title — a day early, every time.
  static DateMatch? _weekdayOfNextWeek(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final int target = _weekdays[match[1] ?? match[3]!]!;
    final String? dayPart = match[2] ?? match[4];
    return DateMatch(
      date: nextWeekWeekday(now.date, target),
      start: match.start,
      end: match.end,
      impliedMinute: dayPart == null
          ? null
          : TimeGrammar.dayPartMinute(dayPart),
      weekday: target,
    );
  }

  static DateMatch? _weekend(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final LocalDate today = now.date;
    final bool next = match[1] == 'next';
    final LocalDate date = next
        ? nextWeekWeekday(today, DateTime.saturday)
        // Said on a Saturday or a Sunday, "this weekend" is the one you are in.
        : (today.weekday >= DateTime.saturday
              ? today
              : forwardWeekday(today, DateTime.saturday, allowToday: true));
    return DateMatch(
      date: date,
      start: match.start,
      end: match.end,
      confidence: Confidence.low,
    );
  }

  static DateMatch? _nextWeek(RegExpMatch m, LocalDateTime now, String t) =>
      DateMatch(
        date: nextWeekWeekday(now.date, DateTime.monday),
        start: m.start,
        end: m.end,
        // Which day of next week is anyone's guess, so the Confirm card asks.
        confidence: Confidence.low,
      );

  static DateMatch? _nextMonth(RegExpMatch m, LocalDateTime now, String t) =>
      DateMatch(
        date: LocalDate(now.date.year, now.date.month, 1).addMonths(1),
        start: m.start,
        end: m.end,
        confidence: Confidence.low,
      );

  static DateMatch? _monthEnd(RegExpMatch m, LocalDateTime now, String t) {
    final LocalDate base = m[1] == null
        ? now.date
        : LocalDate(now.date.year, now.date.month, 1).addMonths(1);
    return DateMatch(date: base.lastDayOfMonth, start: m.start, end: m.end);
  }

  static DateMatch? _inDuration(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final int? amount = _amount(match[1]!);
    final String unit = _singular(match[2]!);
    if (amount == null || amount < 1 || amount > 999) return null;
    switch (unit) {
      case 'minute':
      case 'min':
      case 'hour':
      case 'hr':
        return _inMinutes(
          match,
          now,
          unit.startsWith('h') ? amount * 60 : amount,
        );
      case 'day':
        return DateMatch(
          date: now.date.addDays(amount),
          start: match.start,
          end: match.end,
        );
      case 'week':
        return DateMatch(
          date: now.date.addDays(amount * 7),
          start: match.start,
          end: match.end,
        );
      case 'month':
        // addMonths clamps: "in a month" from 31 January is 28 February.
        return DateMatch(
          date: now.date.addMonths(amount),
          start: match.start,
          end: match.end,
        );
      case 'year':
        return DateMatch(
          date: now.date.addMonths(amount * 12),
          start: match.start,
          end: match.end,
        );
    }
    return null;
  }

  static DateMatch _inMinutes(
    RegExpMatch match,
    LocalDateTime now,
    int minutes,
  ) {
    final LocalDateTime at = now.addMinutes(minutes);
    return DateMatch(
      date: at.date,
      start: match.start,
      end: match.end,
      impliedMinute: at.time.minuteOfDay,
      exact: true,
    );
  }

  static DateMatch? _inHalfHour(RegExpMatch m, LocalDateTime now, String t) =>
      _inMinutes(m, now, 30);

  static DateMatch? _inHoursAndAHalf(
    RegExpMatch m,
    LocalDateTime now,
    String t,
  ) {
    final int? hours = _amount(m[1]!);
    if (hours == null || hours < 1) return null;
    return _inMinutes(m, now, (hours * 60) + 30);
  }

  static DateMatch? _inDecimalHours(
    RegExpMatch m,
    LocalDateTime now,
    String t,
  ) {
    // Hundredths of an hour: ".5" and ".50" are both thirty minutes.
    final int fraction = int.parse(m[2]!.padRight(2, '0'));
    final int minutes = (int.parse(m[1]!) * 60) + (fraction * 60 / 100).round();
    return minutes < 1 ? null : _inMinutes(m, now, minutes);
  }

  static DateMatch? _iso(RegExpMatch match, LocalDateTime now, String text) {
    final LocalDate? date = _exactDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    return date == null
        ? null
        : DateMatch(
            date: date,
            start: match.start,
            end: match.end,
            namesMonth: true,
          );
  }

  static DateMatch? _slash(RegExpMatch match, LocalDateTime now, String text) {
    // US order. "9/21" is 21 September; "21/9" is not a date at all, which is
    // better than silently disagreeing with the speaker about which is which.
    final int month = int.parse(match[1]!);
    final int day = int.parse(match[2]!);
    final LocalDate? date = match[3] == null
        ? _yearlessDate(now.date, month, day)
        : _exactDate(_fullYear(match[3]!), month, day);
    return date == null
        ? null
        : DateMatch(
            date: date,
            start: match.start,
            end: match.end,
            namesMonth: true,
          );
  }

  static DateMatch? _monthDay(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) => _namedMonth(match, now, text, monthGroup: 1, dayGroup: 2, yearGroup: 3);

  static DateMatch? _dayMonth(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) => _namedMonth(match, now, text, monthGroup: 2, dayGroup: 1, yearGroup: 3);

  static DateMatch? _namedMonth(
    RegExpMatch match,
    LocalDateTime now,
    String text, {
    required int monthGroup,
    required int dayGroup,
    required int yearGroup,
  }) {
    final int month = _months[match[monthGroup]!]!;
    final String dayText = match[dayGroup]!;
    final int? day =
        int.tryParse(dayText) ??
        _ordinalWords[dayText.replaceAll(RegExp(r'[\s-]+'), ' ')];
    if (day == null) return null;
    final String? year = match[yearGroup];
    final LocalDate? date = year == null
        ? _yearlessDate(now.date, month, day)
        : _exactDate(_fullYear(year), month, day);
    return date == null
        ? null
        : DateMatch(
            date: date,
            start: match.start,
            end: match.end,
            namesMonth: true,
          );
  }

  static DateMatch? _ordinalDay(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    if (_notADate.contains(wordAfter(text, match.end))) return null;
    final int day = int.parse(match[1]!);
    final LocalDate? date = dayOfMonthOnOrAfter(now.date, day);
    return date == null
        ? null
        : DateMatch(
            date: date,
            start: match.start,
            end: match.end,
            dayOfMonth: day,
          );
  }

  static DateMatch? _ordinalWordDay(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    if (_notADate.contains(wordAfter(text, match.end))) return null;
    final int? day =
        _ordinalWords[match[1]!.replaceAll(RegExp(r'[\s-]+'), ' ')];
    if (day == null) return null;
    final LocalDate? date = dayOfMonthOnOrAfter(now.date, day);
    return date == null
        ? null
        : DateMatch(
            date: date,
            start: match.start,
            end: match.end,
            dayOfMonth: day,
          );
  }

  /// "Monday the fifth" — a spelled ordinal with a weekday in front of it.
  ///
  /// ⚠️ Only where the date phrase ends: "Monday the second meeting" and "Friday
  /// the first thing" are counts, and the weekday is the date.
  static DateMatch? _ordinalWordAfterWeekday(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final String next = wordAfter(text, match.end);
    final bool endsPhrase =
        next.isEmpty ||
        RegExp(r'^\s*[.,;:!?]').hasMatch(text.substring(match.end));
    if (!endsPhrase && !_afterDayPhrase.contains(next)) return null;
    // "Monday the second I land" is "the moment I land": the idiom, not the
    // 2nd, which was November's Monday, five weeks late.
    if (match[1] == 'second' && (next == 'i' || next == 'we')) return null;
    return _ordinalWordDay(match, now, text);
  }

  static DateMatch? _bareMonth(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    final String word = match[2]!;
    final int month = _months[word]!;
    final LocalDate today = now.date;
    final LocalDate date = month == today.month
        ? today
        : LocalDate(
            month < today.month ? today.year + 1 : today.year,
            month,
            1,
          );
    return DateMatch(
      date: date,
      start: match.start,
      end: match.end,
      // A month is thirty guesses wide.
      confidence: Confidence.low,
    );
  }

  // ── Word tables ────────────────────────────────────────────────────────────

  static int _fullYear(String digits) {
    final int value = int.parse(digits);
    return digits.length <= 2 ? 2000 + value : value;
  }

  static String _singular(String unit) =>
      unit.endsWith('s') ? unit.substring(0, unit.length - 1) : unit;

  static int? _amount(String spoken) {
    final int? digits = int.tryParse(spoken);
    if (digits != null) return digits;
    return _numberWords[spoken.replaceAll(RegExp(r'\s+'), ' ')];
  }

  static final RegExp _ordinalSuffix = RegExp(r'(st|nd|rd|th)$');

  static const Map<String, int> _numberWords = <String, int>{
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'fifteen': 15,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'a couple of': 2,
    'a few': 3,
  };

  static const Map<String, int> _weekdays = <String, int>{
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tues': 2,
    'tue': 2,
    'wednesday': 3,
    'weds': 3,
    'wed': 3,
    'thursday': 4,
    'thurs': 4,
    'thur': 4,
    'thu': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  static const Map<String, int> _months = <String, int>{
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  /// Day and month names that are also ordinary English words. Only these need
  /// the context guard; "wednesday" means one thing.
  static const Set<String> _ambiguousWords = <String>{
    'mon',
    'tue',
    'tues',
    'wed',
    'weds',
    'thu',
    'thur',
    'thurs',
    'fri',
    'sat',
    'sun',
    'jan',
    'feb',
    'mar',
    'apr',
    'jun',
    'jul',
    'aug',
    'sep',
    'sept',
    'oct',
    'nov',
    'dec',
    'march',
    'may',
    'august',
  };

  static const Set<String> _dateIshPrefixes = <String>{
    'on',
    'by',
    'this',
    'next',
    'last',
    'coming',
    'upcoming',
    'every',
    'until',
    'till',
    'til',
    'before',
    'after',
    'from',
    'due',
    'for',
    'in',
    'at',
    'around',
    'about',
    'since',
    'starting',
    'past',
  };

  /// Nouns that turn an ordinal back into a plain number: "the 3rd edition".
  static const Set<String> _notADate = <String>{
    'edition',
    'floor',
    'time',
    'times',
    'place',
    'row',
    'try',
    'attempt',
    'version',
    'chapter',
    'section',
    'page',
    'item',
    'anniversary',
    'person',
    'lesson',
    'lessons',
    'class',
    'period',
    'lecture',
    'grade',
    'year',
    'week',
    'day',
    'round',
    'stage',
    'level',
    'street',
    'avenue',
    'lane',
    'entrance',
    'gate',
    'door',
    'block',
    'building',
    'house',
    'shift',
    'term',
    'semester',
    'course',
    'episode',
    'season',
    'part',
    'step',
    'draft',
    'question',
    'task',
  };

  /// What may follow "Monday the fifth" for the fifth to be a date: a time,
  /// a joining word, or the speaker going on ("…the fifth I have a call").
  static const Set<String> _afterDayPhrase = <String>{
    'at',
    'in',
    'by',
    'from',
    'around',
    'about',
    'before',
    'after',
    'and',
    'or',
    'then',
    'i',
    'we',
  };

  // ── Patterns ───────────────────────────────────────────────────────────────

  static const Map<String, int> _ordinalWords = <String, int>{
    'first': 1,
    'second': 2,
    'third': 3,
    'fourth': 4,
    'fifth': 5,
    'sixth': 6,
    'seventh': 7,
    'eighth': 8,
    'ninth': 9,
    'tenth': 10,
    'eleventh': 11,
    'twelfth': 12,
    'thirteenth': 13,
    'fourteenth': 14,
    'fifteenth': 15,
    'sixteenth': 16,
    'seventeenth': 17,
    'eighteenth': 18,
    'nineteenth': 19,
    'twentieth': 20,
    'twenty first': 21,
    'twenty second': 22,
    'twenty third': 23,
    'twenty fourth': 24,
    'twenty fifth': 25,
    'twenty sixth': 26,
    'twenty seventh': 27,
    'twenty eighth': 28,
    'twenty ninth': 29,
    'thirtieth': 30,
    'thirty first': 31,
  };

  /// [_ordinalWords] as an alternation, longest first so "twenty first" is
  /// never read as "twenty" + something.
  static const String _ordinalWordPattern =
      r'(?:twenty|thirty)[-\s](?:first|second|third|fourth|fifth|sixth'
      r'|seventh|eighth|ninth)'
      r'|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth'
      r'|nineteenth|twentieth|thirtieth|eleventh|twelfth|first|second|third'
      r'|fourth|fifth|sixth|seventh|eighth|ninth|tenth';

  static const String _monthWords =
      r'january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul'
      r'|august|aug|september|sept|sep|october|oct|november|nov|december|dec';

  static const String _weekdayWords =
      r'monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu'
      r'|friday|fri|saturday|sat|sunday|sun';

  /// Weekdays that cannot be anything else — no "sat", no "sun" — for the
  /// rules that take a weekday where a preposition would stand.
  static const String _fullWeekdayWords =
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday';

  static const String _dayParts = r'morning|afternoon|evening|night';

  /// "in an hour's time", "in two hours' time", "in two hours time" — the
  /// idiom's tail belongs to the phrase. ⚠️ Without it the match stopped at
  /// "hour" and the title came out as "Call Anna 's time".
  static const String _timeTail = r"(?:(?:'s|')?\s+time\b)?";

  /// "in 20 minutes", and how people hedge it: "in about 20 minutes", "in
  /// like an hour". "After two days" is how Uzbek and Russian speakers say
  /// "in two days" — ⚠️ read as nothing, it was the title "After two days to
  /// call Bobur" with no date.
  static const String _inLead =
      r'\b(?:in|after)\s+(?:(?:about|around|like|maybe|approximately'
      r'|roughly|another|just)\s+)?';

  /// "in an hour or so", "in 10 minutes or sooner" — ⚠️ without it the "so"
  /// split the note, and "Or" was a card of its own.
  static const String _orSo =
      r'(?:\s+or\s+(?:so|sooner|earlier|later|less|more|something)\b)?';

  static const String _hourCountWords =
      r'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve';

  static final List<_DateRule> _rules = <_DateRule>[
    _DateRule(
      RegExp(r'\b(?:the\s+)?day\s+after\s+tomorrow\b'),
      _dayAfterTomorrow,
    ),
    _DateRule(
      RegExp(r'\b(?:the\s+)?day\s+before\s+yesterday\b'),
      _dayBeforeYesterday,
    ),
    _DateRule(RegExp('\\btomorrow(?:\\s+($_dayParts))?\\b'), _tomorrow),
    _DateRule(RegExp('\\b(?:later\\s+)?today(?:\\s+($_dayParts))?\\b'), _today),
    _DateRule(RegExp(r'\btonight\b'), _tonight),
    _DateRule(RegExp(r'\blast\s+night\b'), _lastNight),
    _DateRule(RegExp('\\byesterday(?:\\s+($_dayParts))?\\b'), _yesterday),
    _DateRule(RegExp('\\bthis\\s+($_dayParts)\\b'), _thisDayPart),
    _DateRule(
      RegExp(
        r'\b(?:(on|by|for|this\s+coming|this|next|last|past|coming|upcoming)'
        '\\s+)?($_weekdayWords)\\b(?:\\s+($_dayParts))?',
      ),
      _weekday,
    ),
    _DateRule(
      RegExp(r'\b(?:on\s+)?(this\s+coming|this|next|the|coming)\s+weekend\b'),
      _weekend,
    ),
    // Full weekday names only: "next week sat" is not how anyone says it, and
    // "sun" and "sat" are words.
    _DateRule(
      RegExp(
        '\\bnext\\s+week,?\\s+(?:on\\s+)?($_fullWeekdayWords)\\b'
        '(?:\\s+($_dayParts))?'
        '|\\b(?:on\\s+)?($_fullWeekdayWords)(?:\\s+($_dayParts))?'
        '\\s+(?:of\\s+)?next\\s+week\\b',
      ),
      _weekdayOfNextWeek,
    ),
    _DateRule(RegExp(r'\bnext\s+week\b'), _nextWeek),
    _DateRule(
      RegExp(
        r'\b(?:the\s+)?(?:end|last\s+day)\s+of\s+(?:the\s+|this\s+)?'
        r'(next\s+)?month\b',
      ),
      _monthEnd,
    ),
    _DateRule(RegExp(r'\bnext\s+month\b'), _nextMonth),
    _DateRule(
      RegExp(
        '$_inLead'
        r'(a\s+couple\s+of|a\s+few|an?|\d{1,4}|one|two|three|four|five'
        r'|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty)'
        r'\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\b'
        // ⚠️ Not "after two days of rain": how long something lasted.
        r'(?!\s+of\b)'
        '$_orSo$_timeTail',
      ),
      _inDuration,
    ),
    // "in half an hour", "in an hour and a half", "in 1.5 hours". Without
    // these the first was no reminder at all, and the second matched "in an
    // hour": thirty minutes early, with "and a half" left in the title.
    //
    // ⚠️ Hours only, and as whole phrases rather than an optional "and a half"
    // on the rule above, which would swallow "in a day and a half" whole. A
    // hyphen counts as a space: "a half-hour", "two-and-a-half hours".
    _DateRule(
      RegExp(
        '$_inLead'
        r'(?:a\s+)?half[\s-]+(?:an?[\s-]+)?hour\b'
        '$_orSo$_timeTail',
      ),
      _inHalfHour,
    ),
    _DateRule(
      RegExp(
        '$_inLead(an?|$_hourCountWords|\\d{1,2})\\s+(?:hours?|hrs?)'
        r'[\s-]+and[\s-]+a[\s-]+half\b'
        '$_orSo$_timeTail',
      ),
      _inHoursAndAHalf,
    ),
    _DateRule(
      RegExp(
        '$_inLead($_hourCountWords|\\d{1,2})[\\s-]+and[\\s-]+a[\\s-]+half'
        r'[\s-]+(?:hours?|hrs?)\b'
        '$_orSo$_timeTail',
      ),
      _inHoursAndAHalf,
    ),
    // "in 1.5 hours", "in 2.25 hours" — decimal hours, not the clock "2.25".
    _DateRule(
      RegExp(
        '$_inLead'
        r'(\d{1,2})[.,](\d{1,2})\s+(?:hours?|hrs?)\b'
        '$_orSo$_timeTail',
      ),
      _inDecimalHours,
    ),
    _DateRule(RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), _iso),
    _DateRule(RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b'), _slash),
    // "October 1st", "October the 1st" — the "the" only before an ordinal.
    // ⚠️ The "on" in front is part of the phrase: cut without it, "on October
    // 7th at 9 I have an interview" left "On I have an interview".
    _DateRule(
      RegExp(
        '\\b(?:on\\s+)?($_monthWords)\\.?\\s+'
        r'(?:the\s+(?=\d{1,2}(?:st|nd|rd|th)\b))?'
        r'(\d{1,2})(?:st|nd|rd|th)?'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _monthDay,
    ),
    _DateRule(
      RegExp(
        r'\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?'
        '($_monthWords)\\.?'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _dayMonth,
    ),
    // "the first of October", "on October first" — ordinals spelled out.
    //
    // ⚠️ Only in the two shapes that cannot be anything else: "<ordinal> of
    // <month>", and "<month> <ordinal>" behind a preposition. A bare "May
    // first" also reads "I may first call him".
    _DateRule(
      RegExp(
        '\\b(?:the\\s+)?($_ordinalWordPattern)\\s+of\\s+($_monthWords)\\.?'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _dayMonth,
    ),
    _DateRule(
      RegExp(
        '\\b(?:on|by|due|before|until|till|for)\\s+($_monthWords)\\.?\\s+'
        '(?:the\\s+)?($_ordinalWordPattern)'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _monthDay,
    ),
    // "Monday, October fifth", "Thursday morning, October fifteenth" — a
    // weekday stands where the preposition would.
    _DateRule(
      RegExp(
        '(?<=\\b(?:$_fullWeekdayWords)(?:\\s+(?:$_dayParts))?,?\\s+)'
        '($_monthWords)\\.?\\s+'
        '(?:the\\s+)?($_ordinalWordPattern)'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _monthDay,
    ),
    _DateRule(
      RegExp(
        r'\b(?:(?:on|by|due|before|until|till|for)\s+)?the\s+'
        r'(\d{1,2})(?:st|nd|rd|th)\b',
      ),
      _ordinalDay,
    ),
    // "on 25th", "by 3rd" — the "the" whisper leaves out, or the speaker
    // does. ⚠️ Only behind the preposition: a bare "5th" is "the 5th floor"
    // as often as a day.
    _DateRule(
      RegExp(r'\b(?:on|by|due|before|until|till)\s+(\d{1,2})(?:st|nd|rd|th)\b'),
      _ordinalDay,
    ),
    // "Monday the fifth" — see [_ordinalWordAfterWeekday].
    _DateRule(
      RegExp(
        '(?<=\\b(?:$_fullWeekdayWords),?\\s+)the\\s+'
        '($_ordinalWordPattern)\\b',
      ),
      _ordinalWordAfterWeekday,
    ),
    // "on the fifth", "by the fifteenth" — only behind a preposition: a bare
    // "the second" is far more often "the second thing".
    _DateRule(
      RegExp(
        '\\b(?:on|by|due|before|until|till|for)\\s+the\\s+'
        '($_ordinalWordPattern)\\b',
      ),
      _ordinalWordDay,
    ),
    _DateRule(
      RegExp(
        r'\b(in|on|by|during|until|till|before|after|this|next)\s+'
        '($_monthWords)'
        r'\b(?!\s*\.?\s*\d)',
      ),
      _bareMonth,
    ),
  ];
}
