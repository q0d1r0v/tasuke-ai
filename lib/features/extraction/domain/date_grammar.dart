import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

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
  });

  final LocalDate date;
  final int start;
  final int end;

  /// The time the date phrase carried with it — "tomorrow morning" is 09:00,
  /// "in two hours" is an exact clock time. Null when the phrase said nothing
  /// about the time of day.
  final int? impliedMinute;

  final Confidence confidence;

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
    return found;
  }

  static DateMatch? firstMatch(String phrase, {required LocalDateTime now}) {
    final List<DateMatch> all = allMatches(phrase, now: now);
    return all.isEmpty ? null : all.first;
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
        final int minutes = unit.startsWith('h') ? amount * 60 : amount;
        final LocalDateTime at = now.addMinutes(minutes);
        return DateMatch(
          date: at.date,
          start: match.start,
          end: match.end,
          impliedMinute: at.time.minuteOfDay,
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

  static DateMatch? _iso(RegExpMatch match, LocalDateTime now, String text) {
    final LocalDate? date = _exactDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    return date == null
        ? null
        : DateMatch(date: date, start: match.start, end: match.end);
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
        : DateMatch(date: date, start: match.start, end: match.end);
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
    final int day = int.parse(match[dayGroup]!);
    final String? year = match[yearGroup];
    final LocalDate? date = year == null
        ? _yearlessDate(now.date, month, day)
        : _exactDate(_fullYear(year), month, day);
    return date == null
        ? null
        : DateMatch(date: date, start: match.start, end: match.end);
  }

  static DateMatch? _ordinalDay(
    RegExpMatch match,
    LocalDateTime now,
    String text,
  ) {
    if (_notADate.contains(wordAfter(text, match.end))) return null;
    final LocalDate? date = dayOfMonthOnOrAfter(now.date, int.parse(match[1]!));
    return date == null
        ? null
        : DateMatch(date: date, start: match.start, end: match.end);
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
  };

  // ── Patterns ───────────────────────────────────────────────────────────────

  static const String _monthWords =
      r'january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul'
      r'|august|aug|september|sept|sep|october|oct|november|nov|december|dec';

  static const String _weekdayWords =
      r'monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu'
      r'|friday|fri|saturday|sat|sunday|sun';

  static const String _dayParts = r'morning|afternoon|evening|night';

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
        r'\bin\s+(a\s+couple\s+of|a\s+few|an?|\d{1,4}|one|two|three|four|five'
        r'|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty)'
        r'\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\b',
      ),
      _inDuration,
    ),
    _DateRule(RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), _iso),
    _DateRule(RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b'), _slash),
    _DateRule(
      RegExp(
        '\\b($_monthWords)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _monthDay,
    ),
    _DateRule(
      RegExp(
        r'\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?'
        '($_monthWords)\\.?'
        r'(?:,?\s+(\d{4}))?\b',
      ),
      _dayMonth,
    ),
    _DateRule(
      RegExp(
        r'\b(?:(?:on|by|due|before|until|till|for)\s+)?the\s+'
        r'(\d{1,2})(?:st|nd|rd|th)\b',
      ),
      _ordinalDay,
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
