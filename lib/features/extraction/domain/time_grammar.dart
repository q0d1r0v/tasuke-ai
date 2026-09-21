import 'package:tasuke_ai/core/time/local_time_of_day.dart';

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
  const TimeMatch({required this.time, required this.start, required this.end});

  final LocalTimeOfDay time;
  final int start;
  final int end;

  int get length => end - start;

  @override
  String toString() => 'TimeMatch(${time.toIso()}, $start..$end)';
}

typedef _TimeResolver = LocalTimeOfDay? Function(
  RegExpMatch match,
  String text,
);

final class _TimeRule {
  const _TimeRule(this.pattern, this.resolve);

  final RegExp pattern;
  final _TimeResolver resolve;
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
        found.add(TimeMatch(time: time, start: match.start, end: match.end));
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
    if (startsWithDigit &&
        _numberIntroducers.contains(wordBefore(text, match.start))) {
      return null;
    }
    return _colonClock(match, text);
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

  static const String _lead = r'(?:\b(?:at|by|around|about|from)\s+)?';
  static const String _meridiemTail = r'([ap])\.?\s?m\.?(?![a-z])';

  static final List<_TimeRule> _rules = <_TimeRule>[
    // "3 in the afternoon", "9:30 this evening"
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2})(?::(\d{2}))?\s+(?:in\s+the\s+|this\s+)'
        r'(morning|afternoon|evening|night)\b',
      ),
      _clockInDayPart,
    ),
    // "3pm", "3 PM", "3 p.m.", "3:30pm", "12am"
    _TimeRule(
      RegExp(
        '$_lead'
        r'\b(\d{1,2})(?::(\d{2}))?\s*'
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
        r'\b(\d{1,2})\.(\d{2})\b(?![.\d])(?!\s*[ap]\.?\s?m)',
      ),
      _dotClock,
    ),
    // "3 o'clock"
    _TimeRule(RegExp(r'\b(?:at\s+)?(\d{1,2})\s*o\x27\s?clock\b'), _bareHour),
    // "at 3"
    _TimeRule(
      RegExp(
        r'\bat\s+(\d{1,2})\b(?![:.]\d)(?!\s*[ap]\.?\s?m)'
        r'(?!\s*o\x27?\s?clock)'
        r'(?!\s+in\s+the\s+(?:morning|afternoon|evening|night))',
      ),
      _bareHour,
    ),
    // "noon", "midday", "midnight"
    _TimeRule(
      RegExp(r'\b(?:at\s+|around\s+|by\s+)?(noon|midday|midnight)\b'),
      _namedTime,
    ),
    // "in the morning", "this evening", "night"
    _TimeRule(
      RegExp(
        r'\b(?:in\s+the\s+|this\s+|at\s+)?(morning|afternoon|evening|night)\b',
      ),
      _dayPartOnly,
    ),
  ];
}
