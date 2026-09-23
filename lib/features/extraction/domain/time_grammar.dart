import 'package:tasuke_ai/core/time/local_time_of_day.dart';

import 'clause_splitter.dart';
import 'extraction_defaults.dart';

/// Lower-cases ASCII and straightens the typographic apostrophe **without
/// changing the length of the string**, so every index into the folded text
/// still points at the same character in the original.
///
/// ⚠️ `String.toLowerCase()` is not length-preserving: `İ` (U+0130) folds to two
/// code units. The grammars hand their match offsets to the title cleaner,
/// which slices the ORIGINAL clause with them — one such character anywhere in
/// a transcript would shift every later offset and cut the title in the wrong
/// place.
String foldTemporalCase(String input) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final int unit = input.codeUnitAt(i);
    if (unit >= 0x41 && unit <= 0x5A) {
      out.writeCharCode(unit + 0x20);
    } else if (unit == 0x2019) {
      // Whisper emits “o’clock” and “don’t” with U+2019, and every pattern here
      // is written with the straight quote.
      out.writeCharCode(0x27);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// The word that ends immediately before [index], with any punctuation between
/// them skipped. Empty when [index] is at the start of the utterance.
String wordBefore(String text, int index) {
  int end = index.clamp(0, text.length);
  while (end > 0 && !_isWordUnit(text.codeUnitAt(end - 1))) {
    end--;
  }
  int start = end;
  while (start > 0 && _isWordUnit(text.codeUnitAt(start - 1))) {
    start--;
  }
  return text.substring(start, end);
}

/// The word that begins after [index]. Empty at the end of the utterance.
String wordAfter(String text, int index) {
  int start = index.clamp(0, text.length);
  while (start < text.length && !_isWordUnit(text.codeUnitAt(start))) {
    start++;
  }
  int end = start;
  while (end < text.length && _isWordUnit(text.codeUnitAt(end))) {
    end++;
  }
  return text.substring(start, end);
}

// Non-ASCII counts as a word character so that a Cyrillic or Japanese word next
// to "sat" still reads as a word and not as sentence-initial position.
bool _isWordUnit(int unit) =>
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x30 && unit <= 0x39) ||
    unit == 0x27 ||
    unit > 0x7F;

/// One time-of-day phrase, with the span of the utterance that produced it.
final class TimeMatch {
  const TimeMatch({
    required this.time,
    required this.start,
    required this.end,
    this.dayPart,
  });

  final LocalTimeOfDay time;
  final int start;
  final int end;

  /// "morning", "evening"… when the phrase is only a part of the day and
  /// names no clock time — the one kind of match a clock time said elsewhere
  /// in the clause refines rather than contradicts.
  final String? dayPart;

  int get length => end - start;

  @override
  String toString() => 'TimeMatch(${time.toIso()}, $start..$end)';
}

typedef _TimeResolver = LocalTimeOfDay? Function(
  RegExpMatch match,
  String text,
);

final class _TimeRule {
  const _TimeRule(this.pattern, this.resolve, {this.isDayPart = false});

  final RegExp pattern;
  final _TimeResolver resolve;

  /// Whether the rule matches a part of the day alone, in its group 1.
  final bool isDayPart;
}

/// Every clock-time phrase the app understands.
///
/// Deliberately takes no `now`: a time of day is the same time of day whenever
/// it is spoken. Which *day* it lands on is [WhenParser]'s decision, and
/// keeping that out of here is what lets the whole table be asserted with
/// literals.
abstract final class TimeGrammar {
  /// Every valid time phrase in [phrase], best first.
  ///
  /// "Best" is leftmost, then longest: "at 3 in the afternoon" beats the "at 3"
  /// that starts at the same character.
  static List<TimeMatch> allMatches(
    String phrase, {
    int excludeStart = -1,
    int excludeEnd = -1,
  }) {
    final String text = foldTemporalCase(phrase);
    final List<TimeMatch> found = <TimeMatch>[];
    for (int i = 0; i < _rules.length; i++) {
      final _TimeRule rule = _rules[i];
      for (final RegExpMatch match in rule.pattern.allMatches(text)) {
        if (_overlaps(match.start, match.end, excludeStart, excludeEnd)) {
          continue;
        }
        final LocalTimeOfDay? time = rule.resolve(match, text);
        if (time == null) continue;
        found.add(
          TimeMatch(
            time: time,
            start: match.start,
            end: match.end,
            dayPart: rule.isDayPart ? match[1] : null,
          ),
        );
      }
    }
    found.sort((TimeMatch a, TimeMatch b) {
      final int byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.length.compareTo(a.length);
    });
    return found;
  }

  static TimeMatch? firstMatch(
    String phrase, {
    int excludeStart = -1,
    int excludeEnd = -1,
  }) {
    final List<TimeMatch> all = allMatches(
      phrase,
      excludeStart: excludeStart,
      excludeEnd: excludeEnd,
    );
    return all.isEmpty ? null : all.first;
  }

  /// The minute of day a named part of the day means, or null if [word] is not
  /// one. Every value is an [ExtractionDefaults] constant, never a literal.
  static int? dayPartMinute(String word) => switch (word) {
    'morning' => ExtractionDefaults.morningMinute,
    'afternoon' => ExtractionDefaults.afternoonMinute,
    'evening' => ExtractionDefaults.eveningMinute,
    'night' => ExtractionDefaults.nightMinute,
    'noon' || 'midday' => ExtractionDefaults.noonMinute,
    'midnight' => ExtractionDefaults.midnightMinute,
    _ => null,
  };

  /// [clock] read in the part of the day [part]: "at 7" in the evening is
  /// 19:00, "at 3" in the morning is 03:00, "at 2" at night is after
  /// midnight. [clock] is what the clock time meant on its own, read with
  /// the usual 1–6 → afternoon rule.
  ///
  /// Only for a clock time said with no am/pm and not as a 24-hour time —
  /// the caller knows the words; this knows the arithmetic.
  static LocalTimeOfDay clockInDayPart(LocalTimeOfDay clock, String part) {
    final int minute = clock.minuteOfDay;
    const int noon = 12 * 60;
    final int shifted = switch (part) {
      // Read as the afternoon hour only because it was 1–6 — up to 18:59,
      // or "at 6 go running in the morning" stayed at 18:00.
      'morning' when minute >= noon && minute < 19 * 60 => minute - noon,
      'afternoon' || 'evening' when minute < noon => minute + noon,
      // "at 11" at night is 23:00; "at 2" at night is 02:00, not 14:00.
      'night' when minute >= 5 * 60 && minute < noon => minute + noon,
      'night' when minute >= noon && minute < 17 * 60 => minute - noon,
      _ => minute,
    };
    return LocalTimeOfDay(shifted);
  }

  static bool _overlaps(int start, int end, int otherStart, int otherEnd) =>
      otherStart >= 0 && start < otherEnd && otherStart < end;

  // ── Hour readings ──────────────────────────────────────────────────────────

  /// An hour spoken without an am/pm.
  ///
  /// 1–6 are read as the afternoon/evening hour, 7–12 as written. ⚠️ The
  /// tempting alternative — "whichever of 3 and 15 comes next" — makes the same
  /// sentence parse two different ways depending on the minute it was spoken
  /// in, which is untestable and, worse, unexplainable to the user standing in
  /// front of the Confirm screen.
  static int _hourWithoutMeridiem(int hour, {required bool writtenAs24h}) {
    if (writtenAs24h || hour >= 13 || hour == 0) return hour;
    return hour <= 6 ? hour + 12 : hour;
  }

  static int _hourWithMeridiem(int hour, String meridiem) {
    if (hour < 1 || hour > 12) return -1;
    return (hour % 12) + (meridiem == 'p' ? 12 : 0);
  }

  static int _hourInDayPart(int hour, String part) {
    if (part == 'morning') return hour == 12 ? 0 : hour;
    // "12 at night" is midnight; "12 in the afternoon" is noon.
    if (hour == 12) return part == 'night' ? 0 : 12;
    // "2 at night" is after midnight, not 14:00: nobody calls the afternoon
    // night.
    if (part == 'night' && hour >= 1 && hour <= 4) return hour;
    return hour < 12 ? hour + 12 : hour;
  }

  // ── Resolvers ──────────────────────────────────────────────────────────────

  static LocalTimeOfDay? _clockInDayPart(RegExpMatch match, String text) {
    final int? hour = int.tryParse(match[1] ?? '');
    final int minute = int.tryParse(match[2] ?? '0') ?? 0;
    if (hour == null || minute > 59) return null;
    return LocalTimeOfDay.tryFromMinutes(
      (_hourInDayPart(hour, match[3]!) * 60) + minute,
    );
  }

  static LocalTimeOfDay? _meridiem(RegExpMatch match, String text) {
    final int? hour = int.tryParse(match[1] ?? '');
    final int minute = int.tryParse(match[2] ?? '0') ?? 0;
    if (hour == null || minute > 59) return null;
    final int mapped = _hourWithMeridiem(hour, match[3]!);
    if (mapped < 0) return null;
    return LocalTimeOfDay.tryFromMinutes((mapped * 60) + minute);
  }

  static LocalTimeOfDay? _colonClock(RegExpMatch match, String text) {
    final String hourText = match[1]!;
    final int? hour = int.tryParse(hourText);
    final int? minute = int.tryParse(match[2]!);
    if (hour == null || minute == null || minute > 59) return null;
    final int mapped = _hourWithoutMeridiem(
      hour,
      writtenAs24h: hourText.length == 2 && hourText.startsWith('0'),
    );
    return LocalTimeOfDay.tryFromMinutes((mapped * 60) + minute);
  }

  static LocalTimeOfDay? _dotClock(RegExpMatch match, String text) {
    // ⚠️ "version 2.30" and "rule 3.15" are not appointments. The dotted form
    // is real ("15.00" is how half of Europe writes it), so it cannot simply be
    // dropped — it is refused after the handful of words that introduce a
    // number rather than a time.
    final bool startsWithDigit =
        match[0]!.codeUnitAt(0) >= 0x30 && match[0]!.codeUnitAt(0) <= 0x39;
    if (match.start > 0 && r'$€£₽'.contains(text[match.start - 1])) {
      return null;
    }
    if (startsWithDigit &&
        _numberIntroducers.contains(wordBefore(text, match.start))) {
      return null;
    }
    return _colonClock(match, text);
  }

  static LocalTimeOfDay? _compactClock(RegExpMatch match, String text) {
    final int? hour = int.tryParse(match[1]!);
    final int? minute = int.tryParse(match[2]!);
    if (hour == null || minute == null) return null;
    return LocalTimeOfDay.tryFromMinutes((hour * 60) + minute);
  }

  static LocalTimeOfDay? _bareHour(RegExpMatch match, String text) {
    final String hourText = match[1]!;
    final int? hour = int.tryParse(hourText);
    if (hour == null) return null;
    final int mapped = _hourWithoutMeridiem(
      hour,
      writtenAs24h: hourText.length == 2 && hourText.startsWith('0'),
    );
    return LocalTimeOfDay.tryFromMinutes(mapped * 60);
  }

  static LocalTimeOfDay? _deadlineHour(RegExpMatch match, String text) {
    if (!_endsClockTime(text, match.end)) return null;
    return _bareHour(match, text);
  }

  /// Whether a clock time may end at [end]: the clause ends, a joining word,
  /// a day, or the next thing to do follows ("at six call Anna").
  static bool _endsClockTime(String text, int end) {
    final String next = wordAfter(text, end);
    return next.isEmpty ||
        RegExp(r'^\s*[.,;:!?]').hasMatch(text.substring(end)) ||
        _wordHourFollowers.contains(next) ||
        ClauseLexicon.isImperativeVerb(next) ||
        ClauseLexicon.isEventNoun(next);
  }

  static LocalTimeOfDay? _wordHour(RegExpMatch match, String text) {
    // ⚠️ An allowlist of what may follow, not a blocklist of nouns: "look at
    // three apartments", "prices at two shops", "a five star hotel" are
    // counts, and there are more counted nouns than anyone can list. A clock
    // time is followed by the end of the clause, a joining word, a day, or
    // the next thing to do ("at six call Anna").
    if (!_endsClockTime(text, match.end)) return null;
    final int? hour = _hourWords[match[1]!];
    if (hour == null || hour == 0) return null;
    final int minute = switch (match[2]?.replaceAll(RegExp(r'[\s-]+'), ' ')) {
      'fifteen' => 15,
      'thirty' => 30,
      'forty five' => 45,
      _ => 0,
    };
    final String? meridiem = match[3];
    final String? dayPart = match[4];
    final int mapped = meridiem != null
        ? _hourWithMeridiem(hour, meridiem)
        : dayPart != null
        ? _hourInDayPart(hour, dayPart)
        : _hourWithoutMeridiem(hour, writtenAs24h: false);
    if (mapped < 0) return null;
    return LocalTimeOfDay.tryFromMinutes((mapped * 60) + minute);
  }

  /// "in the evening at 7", "in the morning at 7:30", "at night at eleven".
  static LocalTimeOfDay? _dayPartThenClock(RegExpMatch match, String text) {
    final String part = match[1]!;
    final int? hour = match[3] != null
        ? int.tryParse(match[3]!)
        : _hourWords[match[5]!];
    if (hour == null || hour > 23) return null;
    // A number is a clock time only where one can end — spelled out, or said
    // loosely: "in the evening at three restaurants", "in the evening about
    // 5 people come" are counts. ⚠️ Read as 17:00, the "About 5" was cut
    // from the title. Minutes, "o'clock" or am/pm settle it.
    final bool settled =
        match[4] != null || match[7] != null || match[8] != null;
    if (!settled &&
        (match[5] != null || match[2] != 'at') &&
        !_endsClockTime(text, match.end)) {
      return null;
    }
    final int minute = match[4] != null
        ? int.parse(match[4]!)
        : switch (match[6]?.replaceAll(RegExp(r'[\s-]+'), ' ')) {
            'fifteen' => 15,
            'thirty' => 30,
            'forty five' => 45,
            _ => 0,
          };
    if (minute > 59) return null;
    final String? meridiem = match[8];
    final int mapped = meridiem != null
        ? _hourWithMeridiem(hour, meridiem)
        // "in the evening at 18:00" already says which half of the day.
        : hour == 0 || hour > 12
        ? hour
        : _hourInDayPart(hour, part);
    if (mapped < 0) return null;
    return LocalTimeOfDay.tryFromMinutes((mapped * 60) + minute);
  }

  static LocalTimeOfDay? _namedTime(RegExpMatch match, String text) =>
      LocalTimeOfDay.tryFromMinutes(dayPartMinute(match[1]!));

  static LocalTimeOfDay? _dayPartOnly(RegExpMatch match, String text) =>
      LocalTimeOfDay.tryFromMinutes(dayPartMinute(match[1]!));

  static LocalTimeOfDay? _relativeMinutes(RegExpMatch match, String text) {
    final String spoken = match[1]!.replaceAll(RegExp(r'[\s-]+'), ' ');
    final int? minutes = _minuteWords[spoken];
    final int? hour = _hourWords[match[3]!] ?? int.tryParse(match[3]!);
    if (minutes == null || hour == null || hour > 23) return null;
    final int mapped;
    if (match[4] != null) {
      mapped = _hourWithMeridiem(hour, match[4]!);
      if (mapped < 0) return null;
    } else if (match[5] != null) {
      mapped = _hourInDayPart(hour, match[5]!);
    } else {
      mapped = _hourWithoutMeridiem(hour, writtenAs24h: hour >= 13);
    }
    final bool forward = match[2] == 'past' || match[2] == 'after';
    final int total = (mapped * 60) + (forward ? minutes : -minutes);
    // "ten to midnight" is 23:50 — the day before, on the same clock face.
    return LocalTimeOfDay(((total % 1440) + 1440) % 1440);
  }

  // ── Lexicons ───────────────────────────────────────────────────────────────

  static const Set<String> _numberIntroducers = <String>{
    // Money: "pay 5.50 for the taxi" is a price, not ten to six.
    'pay',
    'paid',
    'transfer',
    'send',
    'cost',
    'costs',
    'owe',
    'lend',
    'spend',
    'withdraw',
    'deposit',
    'price',
    'version',
    'v',
    'ver',
    'build',
    'release',
    'no',
    'number',
    'chapter',
    'section',
    'item',
    'rule',
    'step',
    'page',
    'part',
    'level',
    'room',
  };

  static const Map<String, int> _minuteWords = <String, int>{
    'a quarter': 15,
    'quarter': 15,
    'half': 30,
    'five': 5,
    'ten': 10,
    'twenty': 20,
    'twenty five': 25,
  };

  static const Set<String> _wordHourFollowers = <String>{
    'and',
    'or',
    'then',
    'with',
    'to',
    'for',
    'on',
    'in',
    'at',
    'sharp',
    'today',
    'tomorrow',
    'tonight',
    'this',
    'next',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
    'i',
    'we',
  };

  static const Map<String, int> _hourWords = <String, int>{
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
    'noon': 12,
    'midday': 12,
    'midnight': 0,
  };

  // ── Patterns ───────────────────────────────────────────────────────────────
  //
  // Written against ASCII-folded text, so none of them needs to be
  // case-insensitive.

  // ⚠️ "before", "until" and "till" too: a deadline on the clock is a clock
  // time, and the word left behind put "Before send the invoice" in a title.
  static const String _lead =
      r'(?:\b(?:at|by|around|about|from|before|until|till)\s+)?';
  static const String _meridiemTail = r'([ap])\.?\s?m\.?(?![a-z])';

  static final List<_TimeRule> _rules = <_TimeRule>[
    // "in the evening at 7", "in the morning at 7:30", "at night at eleven"
    //
    // ⚠️ The part of the day first, the way people learning English often put
    // it. Without this rule "in the evening" was the leftmost match and won
    // alone: 18:00 instead of 19:00, "in the morning at 7" an alarm at 09:00,
    // two hours late — and "at 7" left in the title.
    _TimeRule(
      RegExp(
        r'\b(?:in\s+the\s+|this\s+|at\s+(?=night))'
        r'(morning|afternoon|evening|night),?\s+(at|around|about|by)\s+'
        r'(?:(\d{1,2})(?:[:.](\d{2}))?\b(?![:.]\d)'
        r'|(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)'
        r'(?:\s+(fifteen|thirty|forty[-\s]five))?\b)'
        r'(\s*o\x27?\s?clock)?'
        r'(?:\s*([ap])\.?\s?m\.?(?![a-z]))?',
      ),
      _dayPartThenClock,
    ),
    // "3 in the afternoon", "9:30 this evening", "11 at night"
    //
    // ⚠️ "at night" too. Without it "pick her up at 11 at night" was 11:00,
    // twelve hours early, with "at night" left in the title.
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2})(?::(\d{2}))?\s+(?:in\s+the\s+|this\s+|at\s+(?=night))'
        r'(morning|afternoon|evening|night)\b',
      ),
      _clockInDayPart,
    ),
    // "3pm", "3 PM", "3 p.m.", "3:30pm", "5.09 pm", "12am"
    //
    // ⚠️ `[:.]`, not `:`. whisper writes "5.09 PM" about as often as "5:09 PM",
    // and with only the colon allowed this rule skipped "5." and matched the
    // "09 pm" inside it — 9 PM. A reminder asked for at 17:09 was scheduled for
    // 21:00, four hours late, with nothing anywhere to say it had happened.
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2})(?:[:.](\d{2}))?\s*'
        '$_meridiemTail',
      ),
      _meridiem,
    ),
    // "509 pm", "1130 am" — hour and minutes run together.
    //
    // whisper renders a spoken "five oh nine P M" this way. Only ever with an
    // explicit am/pm: without one, "buy 500 apples" would be a time.
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2})(\d{2})\s*'
        '$_meridiemTail',
      ),
      _meridiem,
    ),
    // "quarter past three", "half past three", "quarter to four"
    _TimeRule(
      RegExp(
        r'\b(?:at\s+)?(a\s+quarter|quarter|half|five|ten|twenty[-\s]five|twenty)'
        r'\s+(past|after|to|till|til)\s+'
        r'(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve'
        r'|noon|midnight|\d{1,2})'
        r'(?:\s*([ap])\.?\s?m\.?)?'
        r'(?:\s+in\s+the\s+(morning|afternoon|evening|night))?\b',
      ),
      _relativeMinutes,
    ),
    // "15:00", "9:30"
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2}):(\d{2})\b(?!\s*[ap]\.?\s?m)',
      ),
      _colonClock,
    ),
    // "15.00"
    _TimeRule(
      RegExp(
        '$_lead'
        // ⚠️ `(?!\.\d)`, not `(?![.\d])`: "tomorrow at 9.30." ends a
        // sentence, and refusing any dot after it lost the time of every
        // reminder dictated as the last words of a note. Only "2.30.1" — a
        // dot followed by another digit — is a version number.
        r'\b(\d{1,2})\.(\d{2})\b(?!\.\d)(?!\d)(?!\s*[ap]\.?\s?m)',
      ),
      _dotClock,
    ),
    // "at 1709", "at 0900" — a 24-hour clock with the colon dropped.
    //
    // This is what whisper writes for a spoken "seventeen oh nine", and it
    // parsed as nothing at all, so the words stayed in the task title ("The
    // report at 1709") and no reminder was set.
    //
    // ⚠️ Only after "at", and only a valid HH:MM. Without the "at", "send the
    // 2026 report" would be 20:26; with it, the digits are an appointment in
    // every phrasing a to-do list plausibly contains.
    _TimeRule(
      RegExp(r'\bat\s+([01]\d|2[0-3])([0-5]\d)\b(?![:.]\d)(?!\s*[ap]\.?\s?m)'),
      _compactClock,
    ),
    // "3 o'clock"
    _TimeRule(RegExp(r'\b(?:at\s+)?(\d{1,2})\s*o\x27\s?clock\b'), _bareHour),
    // "at 12 midnight", "by twelve noon" — one phrase. ⚠️ Without it "at 12"
    // won as the leftmost match: midnight read as noon, the word left in the
    // title.
    _TimeRule(
      RegExp(
        r'\b(?:(?:at|by|around|about|before|until|till)\s+)?'
        r'(?:12(?:[:.]00)?|twelve)'
        r'(?:\s*o\x27?\s?clock)?\s+(noon|midday|midnight)\b',
      ),
      _namedTime,
    ),
    // "at 3"
    _TimeRule(
      RegExp(
        r'\bat\s+(\d{1,2})\b(?![:.]\d)(?!\s*[ap]\.?\s?m)'
        r'(?!\s*o\x27?\s?clock)'
        r'(?!\s+(?:in\s+the|at)\s+(?:morning|afternoon|evening|night))',
      ),
      _bareHour,
    ),
    // "before 6", "until 4", "by 5" — a deadline on the clock — and "around
    // 11", "about 3", a clock time said loosely.
    //
    // ⚠️ Only where a clock time can end: "before 6 buy the cake", "cook
    // dinner before 6, …". "by 2 people", "before 3 weeks" and "about 5
    // apples" are counts. Without "around", "After that, around 11, I have a
    // meeting" was a card titled "Around 11" and a meeting with no time.
    _TimeRule(
      RegExp(
        r'\b(?:before|until|till|by|around|about)\s+(\d{1,2})\b(?![:.]\d)'
        r'(?!\s*[ap]\.?\s?m)(?!\s*o\x27?\s?clock)'
        r'(?!\s+(?:in\s+the|at)\s+(?:morning|afternoon|evening|night))',
      ),
      _deadlineHour,
    ),
    // "at six", "at nine thirty", "at seven p.m.", "at eight in the evening"
    //
    // whisper spells small numbers out as often as not, and "go to the gym at
    // six" used to come back with no time at all and "at six" left in the
    // title.
    //
    // ⚠️ Only after "at" or "around", and never before a counted noun: "at
    // one point", "at two places", "around three of them" are not clock
    // times. Not "about": "talk about one thing" is far likelier than a time.
    //
    // A deadline too — "cook dinner before six", "until five" — which whisper
    // spells out as often as "before 6". ⚠️ Not "one by one", "two by two".
    _TimeRule(
      RegExp(
        r'(?<!\b(?:one|two|three|four|five|six|seven|eight|nine|ten|step|side'
        r'|day|little)\s)'
        r'\b(?:at|around|before|until|till)\s+'
        r'(one|two|three|four|five|six|seven|eight|nine|ten'
        r'|eleven|twelve)'
        r'(?:\s+(fifteen|thirty|forty[-\s]five))?'
        r'(?:\s*o\x27?\s?clock)?'
        r'(?:\s*([ap])\.?\s?m\.?(?![a-z]))?'
        r'(?:\s+(?:in\s+the\s+|this\s+|at\s+(?=night))'
        r'(morning|afternoon|evening|night))?'
        r'\b',
      ),
      _wordHour,
    ),
    // "noon", "midday", "midnight"
    _TimeRule(
      RegExp(
        r'\b(?:(?:at|around|by|before|until|till)\s+)?(noon|midday|midnight)\b',
      ),
      _namedTime,
    ),
    // "in the morning", "this evening", "night", "every evening"
    //
    // "every" too: left behind, it dangled in the title — "Water the plants
    // every".
    _TimeRule(
      RegExp(
        r'\b(?:in\s+the\s+|this\s+|at\s+|every\s+)?'
        r'(morning|afternoon|evening|night)\b'
        // "the night shift", "an evening class" describe a thing, not a time.
        r'(?!\s+(?:shift|shifts|club|market|bus|train|flight|class|classes'
        r'|school|owl|mode|light|lights|sky|life|out|off|cream|routine)\b)',
      ),
      _dayPartOnly,
      isDayPart: true,
    ),
  ];
}
