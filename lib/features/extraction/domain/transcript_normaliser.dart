import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'clause_splitter.dart';
import 'date_grammar.dart';
import 'non_task.dart';
import 'time_grammar.dart';
import 'when_parser.dart';

/// Puts a whisper transcript back into the words and punctuation that were
/// spoken, before any rule reads it.
///
/// whisper hears a note well and writes it down its own way: a hesitation as
/// "I'm" or "Ugh", "pack the" as "packed the", "buy the" as "by the", "at 7:30
/// in the morning" as "730 in the morning", a pause as quote marks or a stray
/// full stop. Each is one clip in a hundred, and each used to cost the whole
/// note: "So tomorrow packed the suitcase and exchanged some dollars" was one
/// card, because no rule reads "packed" as a task's verb. The rules stay
/// written for how people talk; this undoes how whisper writes it.
///
/// ⚠️ Every rewrite here is one a typed note cannot tell apart from what it
/// meant, so it runs on every transcript, typed or spoken: a past tense only
/// where a task starts and an object follows ("…and asked me to…" is not
/// touched), "by" only where no when follows it ("by Friday" is a deadline),
/// "I'm" only where nothing but a hesitation can stand ("I'm just quickly buy
/// bread", never "I'm going to…").
final class TranscriptNormaliser {
  const TranscriptNormaliser();

  /// [now], when given, keeps a past tense whose when is already over as
  /// said: "Called the bank at 9 this morning" at 15:00 is done, not an
  /// order for a time gone.
  String normalise(String transcript, {LocalDateTime? now}) {
    String text = transcript
        .replaceAll(_quotes, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r' ([,.;:!?])'), (Match m) => m[1]!)
        .trim();
    if (text.isEmpty) return text;
    text = _hesitationsSpelledAsWords(text);
    text = _clockForms(text);
    text = _instructionVerbs(text, now);
    text = _listCommas(text);
    return text;
  }

  // ── Quote marks ────────────────────────────────────────────────────────────

  /// whisper sets a hesitant phrase in quotes — `"Um, so," Sardor called.` —
  /// and left in, they stuck to titles: `Order the taxi to the airport ."`.
  /// Apostrophes stay: "Rustam's", "don't".
  static final RegExp _quotes = RegExp('["“”„«»]');

  // ── Hesitations whisper writes as words ────────────────────────────────────

  /// "Um, okay so…" heard as "I'm okay so…", "Um, just quickly buy bread" as
  /// "I'm just quickly buy bread", "Um, call Jasur" as "I'm called Jasur",
  /// "Um, okay, work stuff" as "On Ok work stuff", "Um, remind me" as
  /// "Unremind me", "…so, uh, the day after tomorrow" as "…so, up the day
  /// after tomorrow".
  ///
  /// ⚠️ "I'm" only where it opens a sentence and what follows cannot follow
  /// it: "I'm going to call Anna", "I'm at the gym now", "I'm so tired", "I'm
  /// just testing" are all kept.
  String _hesitationsSpelledAsWords(String text) {
    String out = text.replaceAllMapped(_sentenceOpeningIm, (Match m) {
      final String rest = text.substring(m.end);
      return _imIsHesitation(rest) ? '${m[1]}Um' : m[0]!;
    });
    out = out.replaceAllMapped(
      _onOkay,
      (Match m) => '${m[1]}${m[2] == 'O' ? 'Um' : 'um'},',
    );
    out = out.replaceAllMapped(
      _unremind,
      (Match m) => '${m[1] == 'U' ? 'Um' : 'um'}, remind',
    );
    return out.replaceAllMapped(_upAsUh, (Match m) {
      final String next = wordAfter(out, m.end);
      final bool name =
          next.isNotEmpty &&
          next != 'I' &&
          _capital.hasMatch(next[0]) &&
          !_capital.hasMatch(next.length > 1 ? next[1] : 'a');
      final String folded = foldTemporalCase(out.substring(m.end));
      if (!name && !_whenAhead.hasMatch(folded)) return m[0]!;
      return '${m[1]}${m[2] == 'U' ? 'Uh' : 'uh'}';
    });
  }

  static final RegExp _sentenceOpeningIm = RegExp(
    '(^|[.!?]\\s+)I[\'’]m(?=[\\s,])',
  );

  static bool _imIsHesitation(String rest) {
    final String folded = foldTemporalCase(rest);
    final String next = wordAfter(folded, 0);
    if (next.isEmpty) return false;
    final int nextEnd = folded.indexOf(next) + next.length;
    final String after = wordAfter(folded, nextEnd);
    final bool comma = RegExp(r'^\s*,').hasMatch(folded.substring(nextEnd));
    // "Um, I need to…" heard as "I'm I need to…": nothing else puts a
    // subject right after "I'm".
    if (next == 'i' || next == 'we') return true;
    switch (next) {
      // "I'm okay, so today…", "I'm okay so…" — not "I'm okay with Friday".
      case 'okay' || 'ok' || 'alright':
        return comma || after == 'so' || after.isEmpty;
      case 'what' || 'um' || 'uh':
        return true;
      // "I'm so, next Tuesday…", "I'm so next Tuesday I have…" — not "I'm so
      // tired", which says how the speaker is.
      case 'so':
        return comma || _whenOrTaskWord(after);
      // "I'm just quickly buy bread" — not "I'm just testing".
      case 'just':
        return after == 'quickly' || _baseVerb(after);
      // "I'm today I still need to…", "I'm tomorrow call Anna" — not "I'm
      // tomorrow in Samarkand", where the speaker says where they will be.
      case 'today' || 'tomorrow' || 'tonight':
        return comma ||
            after == 'i' ||
            after == 'we' ||
            ClauseLexicon.isImperativeVerb(after);
    }
    // "I'm call Anna", "I'm called Jasur about…": no one says "I'm" before a
    // verb's bare or past form in a note — except "I'm need to", how people
    // learning English say "I need to", which the title cleaner reads.
    if (_baseVerb(next)) return true;
    final String? base = pastTenseBase(next);
    if (base == null || !_callVerbs.contains(base)) return false;
    // "I'm called Jasur about the project" — and not "I'm called Anna.",
    // which is somebody saying their name.
    final String said = rest.trimLeft();
    final int objectAt = said.indexOf(' ') + 1;
    final String object = wordAfter(said, objectAt);
    if (object.isEmpty || !_capital.hasMatch(object[0])) return false;
    final int objectEnd = said.indexOf(object, objectAt) + object.length;
    return RegExp(r'^\s+[a-z]').hasMatch(said.substring(objectEnd));
  }

  /// A verb in its bare form that "I'm" can only stand before as a
  /// hesitation. ⚠️ Not the ones that are also adjectives or places — "I'm
  /// back", "I'm set", "I'm clean", "I'm open" — nor "need".
  static bool _baseVerb(String word) =>
      (ClauseLexicon.isImperativeVerb(word) ||
          ClauseLexicon.isLeadingOnlyVerb(word)) &&
      !_adjectivalVerbs.contains(word);

  static const Set<String> _adjectivalVerbs = <String>{
    'back',
    'set',
    'clean',
    'open',
    'be',
    'need',
    'test',
    'empty',
    'top',
    'check',
    'go',
  };

  /// The past forms whisper writes for "call": "I'm called Jasur" is "um,
  /// call Jasur". Only these — "I'm booked", "I'm finished" are said.
  static const Set<String> _callVerbs = <String>{
    'call',
    'text',
    'email',
    'message',
    'phone',
  };

  static bool _whenOrTaskWord(String word) =>
      _whenWords.contains(word) ||
      word == 'i' ||
      word == 'we' ||
      ClauseLexicon.isDiscourseWord(word) ||
      ClauseLexicon.isImperativeVerb(word);

  static const Set<String> _whenWords = <String>{
    'today',
    'tomorrow',
    'tonight',
    'next',
    'this',
    'on',
    'in',
    'at',
    'the',
    'first',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  };

  static final RegExp _onOkay = RegExp(
    r'(^|[.!?]\s+)(O|o)n(?=[\s,]+[Oo][Kk](?:ay)?\b)',
  );

  static final RegExp _unremind = RegExp(r'\b(U|u)nremind\b');

  /// "…so, up the day after tomorrow", "And up Madina asked me…": an "up" no
  /// verb comes before, right before a when or a name.
  static final RegExp _upAsUh = RegExp(
    r'(^|[,;.!?]\s*|\b(?:and|so|And|So)\s+)(U|u)p(?=[\s,]+\S)',
  );

  static final RegExp _whenAhead = RegExp(
    r'^[\s,]+(?:the\s+day\s+after|today|tomorrow|tonight|next\s|this\s)',
  );

  static final RegExp _capital = RegExp('[A-Z]');

  // ── Clock times ────────────────────────────────────────────────────────────

  /// "then a 12 lunch" → "then at 12 lunch", "730 in the morning" → "7:30 in
  /// the morning", "at 4.0" → "at 4", "at 15 0 0" → "at 15:00".
  ///
  /// ⚠️ Each only where the words around it make it a clock time: "a 12" only
  /// after "then"/"and" and before a task or an event ("a 12 pack of eggs" is
  /// kept), "730" only before a part of the day, ".0" and "0 0" only after
  /// "at" or a deadline word ("version 2.0" is kept).
  String _clockForms(String text) {
    String out = text.replaceAllMapped(_thenA, (Match m) {
      final String folded = foldTemporalCase(text);
      final String next = wordAfter(folded, m.end);
      // "then a 12 pack of beer" is a count.
      final int nextEnd = folded.indexOf(next, m.end) + next.length;
      if (wordAfter(folded, nextEnd) == 'of') return m[0]!;
      if (const <String>{
        'pack',
        'set',
        'box',
        'bag',
        'pair',
        'piece',
        'bottle',
        'can',
        'dozen',
        'minute',
        'hour',
        'day',
        'week',
        'month',
        'year',
        'page',
        'percent',
      }.contains(next)) {
        return m[0]!;
      }
      final bool timed =
          ClauseLexicon.isImperativeVerb(next) ||
          ClauseLexicon.isLeadingOnlyVerb(next) ||
          ClauseLexicon.isEventNoun(next) ||
          next == 'pickup' ||
          RegExp(r"^(?:[ap]m|[ap]|o'clock|oclock)$").hasMatch(next);
      return timed ? '${m[1]} at ${m[2]}' : m[0]!;
    });
    out = out.replaceAllMapped(_ordinalHour, (Match m) {
      final String next = m[2]!;
      return ClauseLexicon.isImperativeVerb(next) ||
              ClauseLexicon.isLeadingOnlyVerb(next)
          ? m[1]!
          : m[0]!;
    });
    out = out.replaceAllMapped(_hourMinutesRunTogether, (Match m) {
      final String before = m.start == 0 ? '' : out.substring(0, m.start);
      // A price, or a number that names a thing: "room 730 in the morning".
      if (RegExp(r'[$€£₽#]\s*$').hasMatch(before) ||
          _namesANumber.contains(
            foldTemporalCase(wordBefore(before, before.length)),
          )) {
        return m[0]!;
      }
      if (!const <String>{
        'at',
        'around',
        'about',
        'by',
        'before',
        'until',
        'till',
        'from',
        'to',
        'today',
        'tomorrow',
        'tonight',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      }.contains(foldTemporalCase(wordBefore(before, before.length)))) {
        return m[0]!;
      }
      return '${m[1]}:${m[2]}';
    });
    out = out.replaceAllMapped(_dotZero, (Match m) => m[1]!);
    return out.replaceAllMapped(_spacedZeros, (Match m) => '${m[1]}:00');
  }

  static final RegExp _thenA = RegExp(
    r'\b([Tt]hen|[Aa]nd then)\s+a\s+(\d{1,2}(?:[:.][0-5]\d)?|noon|midnight)'
    r'(?=\s)',
  );

  /// "then at 6th pick up Madina" — "at 6, pick" heard as an ordinal.
  static final RegExp _ordinalHour = RegExp(
    r'\b(at\s+(?:[1-9]|1[0-2]))(?:st|nd|rd|th)(?=\s+([a-z]+))',
  );

  static final RegExp _hourMinutesRunTogether = RegExp(
    r'\b([1-9]|1[0-2])([0-5]\d)(?=\s+(?:in\s+the\s+(?:morning|afternoon|evening)'
    r'|at\s+night|tonight|this\s+(?:morning|afternoon|evening)'
    "|o['’]?\\s?clock)\\b)",
    caseSensitive: false,
  );

  static const Set<String> _namesANumber = <String>{
    'room',
    'number',
    'no',
    'flight',
    'bus',
    'route',
    'gate',
    'page',
    'apartment',
    'office',
    'platform',
    'seat',
    'train',
    'line',
    'code',
    'order',
    'ticket',
  };

  static final RegExp _dotZero = RegExp(
    r'\b((?:at|by|until|till|before|around|about|from)\s+\d{1,2})\.0\b'
    r'(?![.:,]?\d)',
    caseSensitive: false,
  );

  static final RegExp _spacedZeros = RegExp(
    r'\b((?:at|by|until|till|before|around|about|from)\s+\d{1,2})\s+0\s?0\b',
    caseSensitive: false,
  );

  // ── The verb that starts a task ────────────────────────────────────────────

  /// The first word of each task, where whisper wrote another word that
  /// sounds the same: "packed the suitcase" → "pack the suitcase", "sent him
  /// the contract" → "send him…", "by the cake" → "buy the cake", "pickup
  /// Madina" → "pick up Madina", "goes to the pharmacy" → "go to…".
  ///
  /// A task starts a sentence, or follows a comma or a joining word, after
  /// any filler and whens: "So tomorrow packed the suitcase and exchanged
  /// some dollars", "This evening asked the landlord to fix the heater".
  ///
  /// ⚠️ A past tense only with an object after it — "called the bank", not
  /// "Sardor called, he said…" — never "me" or "us" ("…and asked me to buy
  /// bread" is an errand handed over), never after a past day ("yesterday
  /// called the bank"), and never after a clause that reports what somebody
  /// else did ("Madina called and asked Anna to…").
  String _instructionVerbs(String text, LocalDateTime? now) {
    final Map<int, (int, String)> edits = <int, (int, String)>{};
    bool taskBefore = false;
    for (final int boundary in _boundaries(text)) {
      final int limit = _windowEnd(text, boundary);
      final String window = text.substring(boundary, limit);
      final String folded = foldTemporalCase(window);
      final int start = ClauseSplitter.taskStartIn(folded);
      if (start >= folded.length) continue;
      final String word = wordAfter(folded, start);
      final int at = boundary + start;
      if (edits.containsKey(at)) continue;
      bool isTask =
          ClauseLexicon.isImperativeVerb(word) ||
          ClauseLexicon.isLeadingOnlyVerb(word) ||
          ClauseLexicon.isEventNoun(word) ||
          _obligation.hasMatch(folded.substring(0, _clauseEnd(folded, 0)));
      if (_candidate.hasMatch(folded)) {
        final String? replacement = _instructionVerb(
          text,
          at,
          word,
          lead: folded.substring(0, start),
          boundary: boundary,
          taskBefore: taskBefore,
          now: now,
        );
        if (replacement != null) {
          edits[at] = (word.length, replacement);
          isTask = true;
        }
      }
      taskBefore = taskBefore || isTask;
    }
    if (edits.isEmpty) return text;
    final List<int> positions = edits.keys.toList()..sort();
    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (final int at in positions) {
      final (int length, String replacement) = edits[at]!;
      out
        ..write(text.substring(cursor, at))
        ..write(_sameCase(text.substring(at, at + length), replacement));
      cursor = at + length;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }

  /// What the word at [at] should read as, or null to keep it.
  String? _instructionVerb(
    String text,
    int at,
    String word, {
    required String lead,
    required int boundary,
    bool taskBefore = true,
    LocalDateTime? now,
  }) {
    final int end = at + word.length;
    final String next = wordAfter(text, end);
    final String nextFolded = foldTemporalCase(next);
    final bool nextIsName =
        next.isNotEmpty &&
        next != 'I' &&
        _capital.hasMatch(next[0]) &&
        !RegExp(r'^\s*[,.;:!?]').hasMatch(text.substring(end));
    if (word == 'by') return _byAsBuy(text, at) ? 'buy' : null;
    // "pickup Madina", "pickup maddener from her dance class" — not "the
    // pickup is at 5", "pickup time".
    if (word == 'pickup') {
      return nextFolded.isNotEmpty &&
              !_pickupNoun.contains(nextFolded) &&
              !RegExp(r'^\s*[,.;:!?]').hasMatch(text.substring(end))
          ? 'pick up'
          : null;
    }
    if (word == 'goes') return nextFolded == 'to' ? 'go' : null;
    // "Yesterday called the bank", "Booked the table already" — said as
    // done.
    final String clause = foldTemporalCase(
      text.substring(boundary, _clauseEnd(text, boundary)),
    );
    // "then tonight at 10 cent the report to Amma", "scent the photos to
    // Timur" — "send" as whisper hears it where a task starts. ⚠️ Only with
    // the thing sent right after it: kept, the task had no verb the splitter
    // knew, and it was glued onto the task before, time and all. Said as
    // done ("Yesterday cent the contract…", "Sardor called and cent the
    // photos") it is whisper's "sent", which the rules read as done.
    if (word == 'cent' || word == 'scent') {
      if (!_sentThing.contains(nextFolded) ||
          RegExp(r'^\s*[,.;:!?]').hasMatch(text.substring(end))) {
        return null;
      }
      final bool done =
          _pastDay.hasMatch(lead) ||
          _pastDay.hasMatch(clause) ||
          (now != null &&
              const WhenParser().parse(clause, now: now).isOverAt(now)) ||
          _reportedBefore(text, boundary);
      return done ? 'sent' : 'send';
    }
    final String? base = pastTenseBase(word);
    if (base == null) return null;
    if (_pastDay.hasMatch(lead) || _pastDay.hasMatch(clause)) return null;
    if (now != null &&
        const WhenParser().parse(clause, now: now).isOverAt(now)) {
      return null;
    }
    // "Booked the flight for Friday, now pack the bags", "Sent the contract
    // this morning, now wait for his reply" — the "now" sets what is done
    // against what is left to do. ⚠️ Rewritten, the flight became an order
    // to book it.
    if (_nowAfter.hasMatch(text.substring(_clauseEnd(text, boundary)))) {
      return null;
    }
    if (RegExp(r'^\s*[,.;:!?]').hasMatch(text.substring(end))) return null;
    if (!nextIsName &&
        !_objectWords.contains(nextFolded) &&
        !_particles.contains(nextFolded)) {
      return null;
    }
    // "Buy the book, called Atomic Habits" names the book.
    if (base == 'call' &&
        nextIsName &&
        lead.trim().isEmpty &&
        RegExp(r',\s*$').hasMatch(text.substring(0, boundary))) {
      return null;
    }
    if (_reportedBefore(text, boundary)) return null;
    // A past tense is a task only where the note is giving tasks: a when
    // in its clause, a hesitation before it, or a task before it.
    //
    // ⚠️ Not a when that only dates the object: "Booked the flight for
    // Friday", "scheduled the team meeting for Thursday at 11" say when the
    // flight and the meeting are, and are as likely done as not. Rewritten,
    // a report of work done became an order to do it again.
    if (!taskBefore &&
        !_whenIn(_withoutObjectDay(clause)) &&
        !RegExp(r'\b(?:um|uh)\b').hasMatch(lead)) {
      return null;
    }
    return base;
  }

  /// What "send" takes straight after it: the thing, or who it goes to.
  static const Set<String> _sentThing = <String>{
    'the',
    'a',
    'an',
    'it',
    'them',
    'him',
    'her',
    'my',
    'his',
    'our',
    'their',
    'your',
    'this',
    'that',
    'these',
    'those',
  };

  static final RegExp _obligation = RegExp(
    r'\b(?:forget|remember|need|needs|have|has|remind me|want)\s+to\b|\bmust\b|\bshould\b',
  );

  /// [clause] up to a "for" that dates the object: "booked the flight" in
  /// "booked the flight for Friday".
  static String _withoutObjectDay(String clause) {
    final Match? forDay = _forDay.firstMatch(clause);
    return forDay == null ? clause : clause.substring(0, forDay.start);
  }

  static final RegExp _forDay = RegExp(
    r'\bfor\s+(?=(?:next\s+|this\s+|the\s+)?(?:monday|tuesday|wednesday'
    r'|thursday|friday|saturday|sunday|tomorrow|today|tonight|\d))',
  );

  static bool _whenIn(String clause) =>
      TimeGrammar.allMatches(clause).isNotEmpty ||
      DateGrammar.spans(clause).isNotEmpty ||
      RegExp(
        r'\b(?:today|tomorrow|tonight|this (?:morning|afternoon|evening)|next)\b',
      ).hasMatch(clause);

  /// Where the clause that starts at [from] ends: the next comma, stop or
  /// joining word.
  static int _clauseEnd(String text, int from) {
    final Match? next = RegExp(r'[,.;!?]|\b(?:and|then|but)\b')
        .firstMatch(text.substring(from));
    return next == null ? text.length : from + next.start;
  }

  /// "by the cake", "by bread and kefir", "by a new charger" — "buy" as
  /// whisper hears it when it opens a task. Null-safe: "by Friday", "by 5",
  /// "by the 25th", "by the end of the week", "by train", "by Anna" are
  /// kept.
  static bool _byAsBuy(String text, int at) {
    final String folded = foldTemporalCase(text);
    final int after = at + 2;
    final String next = wordAfter(folded, after);
    if (next.isEmpty) return false;
    final String said = wordAfter(text, after);
    if (said.isNotEmpty && _capital.hasMatch(said[0])) return false;
    if (_notBought.contains(next) || RegExp(r'\d').hasMatch(next)) return false;
    // "Then by the bakery pick up bread": the task has its verb, and the
    // "by" says where. ⚠️ A verb, not a noun that is one too: "by a new
    // charger for my phone" — after a determiner or a preposition, "phone" is
    // the thing.
    final String phrase = folded.substring(after, _clauseEnd(folded, after));
    String previous = '';
    for (final RegExpMatch m in RegExp(r"[a-z][a-z']*").allMatches(phrase)) {
      final String w = m[0]!;
      if (previous.isNotEmpty &&
          ClauseLexicon.isImperativeVerb(w) &&
          !ClauseLexicon.isClauseHead(previous)) {
        return false;
      }
      previous = w;
    }
    // A when the grammars read, starting at the "by" or right after it.
    final String rest = folded.substring(at, _windowEnd(folded, at));
    if (TimeGrammar.allMatches(rest).any((TimeMatch m) => m.start <= 3) ||
        DateGrammar.spans(rest).any(((int, int) s) => s.$1 <= 3)) {
      return false;
    }
    if (_determinersForBuy.contains(next)) {
      final int nextEnd = folded.indexOf(next, after) + next.length;
      final String thing = wordAfter(folded, nextEnd);
      if (thing.isEmpty ||
          _notBought.contains(thing) ||
          RegExp(r'\d').hasMatch(thing)) {
        return false;
      }
      // "by the meeting", "by the birthday party" say by when; "by a
      // birthday cake" names a thing to buy, whatever the word before it.
      // ⚠️ Judged on the first word alone, the cake stayed "By a birthday
      // cake for Nodira" — a card with no verb.
      return !ClauseLexicon.isEventNoun(_headNoun(folded, nextEnd));
    }
    return !ClauseLexicon.isClauseHead(next) &&
        !ClauseLexicon.isEventNoun(next) &&
        !ClauseLexicon.isImperativeVerb(next);
  }

  /// The last word of the noun phrase that starts at [from]: "cake" in "a
  /// birthday cake for Nodira", "party" in "the birthday party on Friday".
  static String _headNoun(String folded, int from) {
    String head = '';
    int at = from;
    for (int i = 0; i < 4; i++) {
      final String word = wordAfter(folded, at);
      if (word.isEmpty ||
          ClauseLexicon.isClauseHead(word) ||
          _whenWords.contains(word) ||
          ClauseLexicon.isImperativeVerb(word) ||
          RegExp(r'^[,.;:!?]').hasMatch(folded.substring(at).trimLeft())) {
        break;
      }
      head = word;
      at = folded.indexOf(word, at) + word.length;
    }
    return head;
  }

  static const Set<String> _pickupNoun = <String>{
    'is',
    'was',
    'will',
    'at',
    'truck',
    'time',
    'point',
    'location',
    'line',
    'order',
    'window',
    'date',
    'lines',
  };

  static const Set<String> _determinersForBuy = <String>{
    'a',
    'an',
    'the',
    'some',
    'new',
    'fresh',
    'more',
    'two',
    'three',
    'four',
    'five',
    'six',
    'ten',
  };

  /// What follows a "by" that is not "buy": a when, a way of going, a person.
  static const Set<String> _notBought = <String>{
    'end',
    'way',
    'time',
    'then',
    'now',
    'latest',
    'same',
    'next',
    'weekend',
    'morning',
    'afternoon',
    'evening',
    'night',
    'noon',
    'midnight',
    'deadline',
    'beginning',
    'middle',
    'start',
    'day',
    'week',
    'month',
    'year',
    'following',
    'first',
    'last',
    'car',
    'bus',
    'train',
    'taxi',
    'plane',
    'metro',
    'foot',
    'bike',
    'phone',
    'email',
    'mail',
    'post',
    'hand',
    'text',
    'message',
    'cash',
    'card',
    'me',
    'us',
    'him',
    'her',
    'them',
    'you',
    'myself',
    'far',
    'default',
    'chance',
    'mistake',
    'accident',
    'itself',
    'heart',
  };

  /// What stands after a verb that has its object: a determiner, a pronoun
  /// for a thing or a third person.
  static const Set<String> _objectWords = <String>{
    'the',
    'a',
    'an',
    'my',
    'your',
    'his',
    'her',
    'our',
    'their',
    'some',
    'all',
    'this',
    'that',
    'these',
    'those',
    'him',
    'them',
    'it',
    'two',
    'three',
    'four',
    'five',
    'new',
  };

  /// "replied to", "packed up", "checked in", "canceled for good".
  static const Set<String> _particles = <String>{
    'to',
    'up',
    'off',
    'out',
    'in',
    'back',
    'over',
    'down',
    'with',
    'for',
    'about',
  };

  static final RegExp _nowAfter = RegExp(
    r'^\s*[,;.!]?\s*(?:(?:and|so)\s+)?now\b',
    caseSensitive: false,
  );

  static final RegExp _pastDay = RegExp(
    r'\b(?:yesterday|last|ago|earlier|already)\b',
  );

  /// Whether the clause before the joining word at [boundary] says what
  /// somebody else did: "Sardor called and asked Anna to…", "my mom texted
  /// and sent the photos".
  static bool _reportedBefore(String text, int boundary) {
    if (boundary == 0) return false;
    final String before = text.substring(0, boundary);
    final int cut = before.lastIndexOf(RegExp(r'[.,;!?]'));
    final String clause = before.substring(cut + 1).trim();
    if (clause.isEmpty) return false;
    return NonTask.isReport(clause) ||
        NonTask.isAboutSomeoneElse(clause) ||
        _someoneDid.hasMatch(clause);
  }

  static final RegExp _someoneDid = RegExp(
    r"^(?:(?:[Mm]y|[Oo]ur|[Hh]is|[Hh]er|[Tt]he)\s+[a-z']+|[Hh]e|[Ss]he|[Tt]hey"
    r"|(?!(?:It|This|That|There)\b)[A-Z][a-z']+)\s+"
    r'(?:[a-z]+ed|sent|said|told|wrote|came|went)\b',
  );

  /// See [ClauseLexicon.pastTenseBase].
  static String? pastTenseBase(String word) =>
      ClauseLexicon.pastTenseBase(word);

  /// Where a task may start in [text]: its start, after a stop or a comma,
  /// after a joining word.
  static Iterable<int> _boundaries(String text) sync* {
    yield 0;
    for (final RegExpMatch m in _boundary.allMatches(text)) {
      if (m.end < text.length) yield m.end;
    }
  }

  static final RegExp _candidate = RegExp(
    r'\b(?:[a-z]+ed|sent|by|pickup|goes|cent|scent)\b',
  );

  static final RegExp _boundary = RegExp(
    r'[.!?;:,]\s*|\b(?:and|then|also|so|but|plus|And|Then|Also|So|But|Plus)\s+',
  );

  /// Where the words after [from] that can hold one task's start end: the
  /// next stop or comma, and never more than a short phrase — the grammars
  /// run on it, once for every boundary.
  static int _windowEnd(String text, int from) {
    final int stop = text.indexOf(RegExp(r'[.!?;]\s'), from);
    final int limit = from + 120;
    int end = stop < 0 ? text.length : stop;
    if (end > limit) end = limit;
    return end < text.length ? end : text.length;
  }

  static String _sameCase(String said, String replacement) =>
      said.isNotEmpty && _capital.hasMatch(said[0])
      ? '${replacement[0].toUpperCase()}${replacement.substring(1)}'
      : replacement;

  // ── Commas whisper left out ────────────────────────────────────────────────

  /// "Remind me to call Nargiza at 4 about the menu to order the cake on
  /// Monday to check the hall tomorrow and to buy balloons" — the list of
  /// "to"s said with the pauses and heard without the commas; "…farewell
  /// party at 7pm he is moving to Korea" — somebody else's news run into
  /// the task; "…return the books Meet Nadira at 12" — a sentence whisper
  /// began with a capital and no stop before it.
  ///
  /// ⚠️ Only where the list is certain: a "to" list needs its closing "and
  /// to…", no comma of its own, and four items or a when in the middle one
  /// ("remind me to call Anna to ask about the party and to buy a gift" is
  /// one call and its purpose); a "he is …ing" only right after the when that
  /// ends the task ("tell mom she is coming with us" is one task); a
  /// capitalised verb only after a word that ends a phrase ("the books Meet
  /// Nadira", not "watch Clean Code").
  String _listCommas(String text) {
    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (final RegExpMatch s in RegExp(r'[^.!?]+[.!?]*').allMatches(text)) {
      out.write(text.substring(cursor, s.start));
      out.write(_toListCommas(s[0]!));
      cursor = s.end;
    }
    out.write(text.substring(cursor));
    String result = out.toString();
    result = result.replaceAllMapped(_newsRunOn, (Match m) {
      final String before = foldTemporalCase(m[1]!);
      // Only after the when that ends the task: "…party at 7pm he is moving
      // to Korea". "Tell mom she is coming" is one task.
      if (!_endsWhen.hasMatch(before)) return m[0]!;
      return '${m[1]}, ${m[2]}';
    });
    return result.replaceAllMapped(_capitalisedVerb, (Match m) {
      final String before = m[1]!;
      final String verb = foldTemporalCase(m[2]!);
      if (!ClauseLexicon.isImperativeVerb(verb) ||
          ClauseLexicon.isClauseHead(before) ||
          ClauseLexicon.isDiscourseWord(before) ||
          ClauseLexicon.isImperativeVerb(before) ||
          ClauseLexicon.isLeadingOnlyVerb(before) ||
          _titleIntro.contains(before.toLowerCase())) {
        return m[0]!;
      }
      return '$before, ${m[2]}';
    });
  }

  String _toListCommas(String sentence) {
    final String folded = foldTemporalCase(sentence);
    final List<RegExpMatch> tos = <RegExpMatch>[
      for (final RegExpMatch m in _toVerb.allMatches(folded))
        if (ClauseLexicon.isImperativeVerb(m[2]!) ||
            ClauseLexicon.isLeadingOnlyVerb(m[2]!))
          m,
    ];
    if (tos.length < 3 || !RegExp(r'\band\s*$').hasMatch(tos.last[1]!)) {
      return sentence;
    }
    // A list typed with its commas has none missing: "…to the bank to pay
    // the bill, to call Anna and to buy milk" keeps the bill with the bank.
    if (folded.substring(tos.first.end, tos.last.start).contains(',')) {
      return sentence;
    }
    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (int i = 1; i < tos.length - 1; i++) {
      final RegExpMatch m = tos[i];
      final String before = m[1]!;
      if (before.contains(',') || before.contains('and')) continue;
      // "remind me to ask Timur to call me and to send the photos": what
      // Timur is asked to do, not the next item.
      if (_asksSomeone.contains(tos[i - 1][2])) continue;
      // Of three, the middle one may be the first one's purpose — "to call
      // Anna to ask about the party and to buy a gift" — unless it has a
      // when of its own, which a purpose does not.
      if (tos.length < 4 &&
          !_hasWhen(folded.substring(m.start, tos[i + 1].start))) {
        continue;
      }
      if (_modalTo.contains(wordBefore(folded, m.start + before.length))) {
        continue;
      }
      final int at = m.start + before.length - before.trimLeft().length;
      final int trimmedAt = folded.substring(0, at).trimRight().length;
      out
        ..write(sentence.substring(cursor, trimmedAt))
        ..write(',');
      cursor = trimmedAt;
    }
    out.write(sentence.substring(cursor));
    return out.toString();
  }

  static bool _hasWhen(String folded) =>
      TimeGrammar.allMatches(folded).isNotEmpty ||
      DateGrammar.spans(folded).isNotEmpty;

  /// " to call", ", to order", " and to buy" — group 1 is what stands before
  /// the "to".
  static final RegExp _toVerb = RegExp(
    r'((?:\s*,)?\s+(?:and\s+)?)to\s+([a-z]+)',
  );

  /// Verbs whose object is given the next "to…" to do.
  static const Set<String> _asksSomeone = <String>{
    'ask',
    'tell',
    'remind',
    'get',
    'let',
    'help',
    'teach',
    'invite',
  };

  static const Set<String> _modalTo = <String>{
    'have',
    'has',
    'had',
    'need',
    'needs',
    'want',
    'wants',
    'going',
    'got',
    'ought',
    'used',
    'able',
    'how',
    'order',
    'as',
    'me',
    'us',
  };

  static final RegExp _newsRunOn = RegExp(
    r"([A-Za-z0-9.']+) ((?:he|she|they|He|She|They)(?: is| are| was| were|'s|'re)"
    r' [a-z]+ing\b)',
  );

  /// The last word of a when: "7pm", "7", "7:30", "5th", "tomorrow",
  /// "evening", "Friday".
  static final RegExp _endsWhen = RegExp(
    r'^(?:\d{1,2}(?:[:.]\d{2})?(?:[ap]\.?m\.?)?|\d{1,2}(?:st|nd|rd|th)|[ap]\.m\.?'
    r"|o'clock|noon|midnight|today|tomorrow|tonight|morning|afternoon|evening"
    r'|night|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$',
  );

  static const Set<String> _titleIntro = <String>{
    'movie',
    'film',
    'book',
    'song',
    'album',
    'app',
    'show',
    'series',
    'podcast',
    'game',
    'chapter',
    'article',
    'video',
    'course',
    'channel',
    'called',
    'named',
    'titled',
    'near',
    'behind',
    'beside',
    'opposite',
    'outside',
    'inside',
    'past',
    'via',
    'around',
    'across',
    'next',
    'like',
  };

  static final RegExp _capitalisedVerb = RegExp(
    r"\b([a-z][a-z']*) ([A-Z][a-z]+)(?= (?:[a-z]|[A-Z][a-z]))",
  );
}
