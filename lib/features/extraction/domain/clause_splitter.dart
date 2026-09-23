import 'date_grammar.dart';
import 'non_task.dart';
import 'time_grammar.dart';

/// The word lists the splitter and the date grammar must agree on.
///
/// They live together because they answer the same question from two sides:
/// the splitter asks "is this fragment a task of its own", and the date
/// grammar's guard asks "is this sentence-initial `Sat` a day or a verb".
/// Two copies of the verb list would drift, and the drift would show up as
/// "Sun is out" becoming a Sunday task.
abstract final class ClauseLexicon {
  /// Verbs people actually start a spoken task with.
  ///
  /// ⚠️ Nouns that double as verbs are deliberately absent — `build`, `note`,
  /// `release`, `plan`, `report`, `file`, `post`, `mail`. Every one of them
  /// turns "send the build and the release notes to James" into two tasks,
  /// which is the exact bug this lexicon exists to prevent.
  static bool isImperativeVerb(String word) => _verbs.contains(word);

  /// Verbs that are also everyday nouns or adjectives — "sort", "empty",
  /// "ring", "look", "wish". They start a task only as its first word ("sort
  /// the mail"), never from inside one ("a ring for Anna").
  static bool isLeadingOnlyVerb(String word) => _leadingOnly.contains(word);

  /// The verb behind a progressive: "calling" → call, "meeting" → meet,
  /// "picking" → pick, "going" → go, "taking" → take, "shopping" → shop.
  /// Null when the stem is not a verb a task starts with ("jumping").
  static String? progressiveVerb(String word) {
    if (word.length < 5 || !word.endsWith('ing')) return null;
    final String base = word.substring(0, word.length - 3);
    final List<String> candidates = <String>[
      base,
      '${base}e',
      if (base.length > 2 && base[base.length - 1] == base[base.length - 2])
        base.substring(0, base.length - 1),
    ];
    for (final String stem in candidates) {
      // "I'm being silly" is not a plan to be anything.
      if (stem == 'be') continue;
      if (_verbs.contains(stem) || _leadingOnly.contains(stem)) return stem;
    }
    return null;
  }

  static const Set<String> _leadingOnly = <String>{
    'sort',
    'empty',
    'ring',
    'look',
    'wish',
    'check',
    // "turn off the oven", "let the electrician in", "stop at the pharmacy",
    // "exchange some dollars", "play football", "top up the card", "answer
    // the emails" — and "my turn", "a bus stop", "the exchange rate", "a
    // play", "on top", "the answer" from inside one.
    'turn',
    'let',
    'stop',
    'exchange',
    'play',
    'top',
    'answer',
    // "be at home for the plumber" — and "it will be fun" from inside one.
    'be',
    // "Before leaving lock the door, turn off the gas", "…, brush teeth" —
    // and "buy a lock", "a new brush" from inside one. ⚠️ Unknown, the verb
    // was not seen after "before leaving", which was then read as a
    // condition, and the door went with it.
    'lock',
    'brush',
  };

  /// "at some point", "whenever I have time", "no rush" — the speaker saying
  /// the task has no date, which is not the same as saying nothing about it:
  /// the day of the task before it must not be carried over.
  ///
  /// ⚠️ "eventually", "someday", "one day", "later this week" too: in
  /// "Visit grandma on Saturday and eventually fix her fence" the fence had
  /// Saturday, and "Someday" was a card of its own. Not "for one day", "one
  /// day before", "one day off": a length, a count back, a thing.
  static final RegExp vagueWhen = RegExp(
    r'\b(?:at\s+some\s+point|(?:later|sometime)\s+this\s+(?:week|month|year)'
    r'|sometime(?:\s+(?:soon|later))?'
    r'|when(?:ever)?\s+(?:i|we)\s+(?:have|get|find)\s+(?:the\s+|some\s+)?time'
    r'|whenever\s+(?:i|we)\s+can|one\s+of\s+these\s+days'
    r'|eventually|some\s?day|sooner\s+or\s+later'
    r'|in\s+the\s+(?:near\s+|distant\s+)?future'
    r'|(?<!\b(?:for|in|within|only|just|per|a|every|than|of|about|over|the'
    r'|that|this|same|one)\s)one\s+day(?!\s+(?:a|per|each|before|after|early'
    r'|earlier|late|later|ahead|in\s+advance|off|trip|pass|ticket|tour|course'
    r'|visa|delivery|shipping|only|left)\b)'
    r'|no\s+rush|no\s+hurry)\b',
  );

  /// Words no task starts with. A fragment that opens with one of these is a
  /// continuation of the previous clause, not a new one.
  static bool isClauseHead(String word) => _heads.contains(word);

  /// The base form of [word] when it is the past tense of a verb a task
  /// starts with — "called" → call, "packed" → pack, "exchanged" →
  /// exchange, "replied" → reply, "cancelled" → cancel, "sent" → send — or
  /// null.
  static String? pastTenseBase(String word) {
    if (word == 'sent') return 'send';
    if (word.length < 5) return null;
    final List<String> candidates = <String>[
      if (word.endsWith('ied')) '${word.substring(0, word.length - 3)}y',
      if (word.endsWith('ed')) ...<String>[
        word.substring(0, word.length - 2),
        word.substring(0, word.length - 1),
        if (word.length > 5 && word[word.length - 3] == word[word.length - 4])
          word.substring(0, word.length - 3),
      ],
    ];
    for (final String stem in candidates) {
      if (stem == 'need' || stem == 'be') continue;
      if (isImperativeVerb(stem) || isLeadingOnlyVerb(stem)) return stem;
    }
    return null;
  }

  /// Whether [word] is the past tense of a verb a task starts with, regular
  /// ("fixed", "called") or not ("paid", "bought", "went", "took").
  ///
  /// ⚠️ Only to tell a thing already done; never to rewrite one into an
  /// order, which [pastTenseBase] alone decides. Not the past tenses spelled
  /// like the verb ("put", "set", "read", "cut"): "Put the milk in the
  /// fridge" is an order.
  static bool isPastTense(String word) =>
      pastTenseBase(word) != null || _irregularPast.contains(word);

  static const Set<String> _irregularPast = <String>{
    'paid',
    'bought',
    'went',
    'took',
    'got',
    'made',
    'brought',
    'gave',
    'wrote',
    'told',
    'met',
    'left',
    'found',
    'sold',
    'did',
    'drove',
    'ate',
    'spoke',
    'rang',
    'threw',
    'kept',
    'fed',
    'swept',
    'hung',
    'lent',
    'spent',
    'taught',
    'caught',
    'withdrew',
    'drew',
    'chose',
    'flew',
    'ran',
    'sang',
    'sent',
    'built',
    'held',
    'won',
    'wore',
    'woke',
  };

  /// Things people schedule without a verb: "lunch with Dilnoza at twelve",
  /// "doctor appointment next Monday". A fragment that opens with one is a
  /// task of its own.
  static bool isEventNoun(String word) => _events.contains(word);

  /// Words people say before a task that are not part of it: "okay, so first
  /// I need to…", "second, print it", "um, call Anna".
  static bool isDiscourseWord(String word) =>
      _discourse.contains(word) || _hesitationWords.contains(word);

  /// The sounds people make while they think, as whisper spells them — one
  /// list for every pattern that skips them, so the splitter, the title
  /// cleaner and [NonTask] cannot drift apart.
  ///
  /// ⚠️ "eh", "ee" and "mm" too, not only the English "um"/"uh": "eh" is how
  /// Uzbek and Russian speakers hesitate, and "Eh, call Anna at 5" came back
  /// as two cards, one of them titled "Eh". And every length whisper spells
  /// them in — "Ugh. Call the car dealer" was a card titled "Ugh".
  static const String hesitations =
      'um|umm|ummm|uh|uhh|uhhh|ugh|uhm|er|erm|hmm|hmmm|hm|eh|ehh|ehm|ee|mm|mmm';

  static final Set<String> _hesitationWords = hesitations.split('|').toSet();

  /// Words that are filler only when commas set them off: "I have to, like,
  /// buy milk", "Like, buy eggs at 6" — never "I'd like to…" or "a dress
  /// like this", where they are the task.
  static bool isSetOffFiller(String word) => word == 'like';

  /// Whether the word at [at] in [folded] is said as filler: a discourse word,
  /// unless it is one that doubles as a verb and its preposition follows.
  ///
  /// ⚠️ "Uh, listen, call the bank" but "listen to the podcast": skipped as
  /// filler, the verb was cut and the title came out "To the podcast".
  static bool isFillerAt(String folded, int at) {
    final String word = wordAfter(folded, at);
    if (isSetOffFiller(word)) {
      final int start = folded.indexOf(word, at);
      return _commaOrEdge(folded, start, -1) &&
          _commaOrEdge(folded, start + word.length, 1);
    }
    if (!isDiscourseWord(word)) return false;
    final int start = folded.indexOf(word, at);
    // ⚠️ "Buy drill bits, 8 mm, and wood screws": after a number "mm" is
    // millimetres, and skipped as a sound it took the "8" with it into the
    // next item — "Buy drill bits and 8 mm, wood screws".
    if (_hesitationWords.contains(word) && _afterNumber(folded, start)) {
      return false;
    }
    final String? object = _discourseVerbs[word];
    return object == null || wordAfter(folded, start + word.length) != object;
  }

  /// Whether a digit comes right before [at], spaces aside: "8 mm", "5mm".
  static bool _afterNumber(String text, int at) {
    int i = at - 1;
    while (i >= 0 && text[i] == ' ') {
      i--;
    }
    return i >= 0 && text.codeUnitAt(i) >= 0x30 && text.codeUnitAt(i) <= 0x39;
  }

  /// Whether the first character past the spaces from [from] in direction
  /// [step] is a comma, or there is none: the word there is set off.
  static bool _commaOrEdge(String text, int from, int step) {
    int i = step < 0 ? from - 1 : from;
    while (i >= 0 && i < text.length && text[i] == ' ') {
      i += step;
    }
    return i < 0 || i >= text.length || text[i] == ',';
  }

  static const Map<String, String> _discourseVerbs = <String, String>{
    'listen': 'to',
  };

  static const Set<String> _events = <String>{
    'appointment',
    'birthday',
    'breakfast',
    'checkup',
    'class',
    'conference',
    'dentist',
    'dinner',
    'doctor',
    'exam',
    'flight',
    'haircut',
    'interview',
    'lecture',
    'lesson',
    'lunch',
    'meeting',
    'party',
    'photoshoot',
    'rehearsal',
    'session',
    'shift',
    'shoot',
    'standup',
    'training',
    'webinar',
    'wedding',
    'workout',
    'gym',
    'football',
    'yoga',
    'match',
    'game',
  };

  // The hesitation sounds are in [hesitations].
  static const Set<String> _discourse = <String>{
    'okay',
    'ok',
    'so',
    'well',
    'alright',
    'first',
    'firstly',
    'second',
    'secondly',
    'third',
    'thirdly',
    'finally',
    'lastly',
    'oh',
    'yeah',
    'anyway',
    'actually',
    'then',
    'also',
    'and',
    'please',
    // "Um, just quickly, buy bread", "Ah yes, …", "Ooh, …", "…, wow."
    'just',
    'quickly',
    'ah',
    'ooh',
    'wow',
    'honestly',
    'basically',
    'listen',
  };

  static const Set<String> _verbs = <String>{
    'add',
    'apply',
    'arrange',
    'ask',
    'bake',
    'borrow',
    'attend',
    'back',
    'book',
    'bring',
    'buy',
    'call',
    'cancel',
    'change',
    'charge',
    'check',
    'clean',
    'collect',
    'confirm',
    'cook',
    'create',
    'cut',
    'delete',
    'deliver',
    'deploy',
    'decorate',
    'defrost',
    'discuss',
    'do',
    'download',
    'drive',
    'draft',
    'drop',
    'email',
    'exercise',
    'feed',
    'fetch',
    'fly',
    'fill',
    'finalise',
    'finalize',
    'find',
    'finish',
    'fix',
    'follow',
    'get',
    'give',
    'go',
    'grab',
    'hire',
    'hang',
    'help',
    'install',
    'iron',
    'invite',
    'join',
    'learn',
    'leave',
    // ⚠️ Also a discourse word — "Listen, the internet is down" — which
    // [ClauseLexicon.isFillerAt] tells apart by the "to" after the verb.
    'listen',
    'make',
    'meet',
    'merge',
    'message',
    'mow',
    'move',
    'open',
    'order',
    'organise',
    'organize',
    'pack',
    'paint',
    'pay',
    'phone',
    'pick',
    'pray',
    'practice',
    'practise',
    'prepare',
    'print',
    'put',
    'read',
    'refill',
    'register',
    'remember',
    'remind',
    'renew',
    'repair',
    'replace',
    'reply',
    'reschedule',
    'research',
    'respond',
    'return',
    'say',
    'review',
    'scan',
    'schedule',
    'see',
    'sell',
    'send',
    'set',
    'share',
    'ship',
    'sign',
    'start',
    'study',
    'submit',
    'sweep',
    'take',
    'talk',
    'tell',
    'test',
    'text',
    'thank',
    'tidy',
    'transfer',
    'translate',
    'try',
    'travel',
    'update',
    'upgrade',
    'upload',
    'vacuum',
    'visit',
    'walk',
    'wash',
    'wake',
    'watch',
    'water',
    'withdraw',
    'wrap',
    'write',
  };

  static const Set<String> _heads = <String>{
    'a',
    'an',
    'the',
    'this',
    'that',
    'these',
    'those',
    'my',
    'his',
    'her',
    'our',
    'their',
    'its',
    'your',
    'some',
    'any',
    'to',
    'for',
    'with',
    'of',
    'at',
    'in',
    'on',
    'by',
    'from',
    'about',
    'into',
    'onto',
    'over',
    'under',
    'and',
    'or',
    'plus',
    'also',
    'then',
    'before',
    'during',
    'without',
  };
}

/// Splits one spoken utterance into the tasks it contains.
final class ClauseSplitter {
  const ClauseSplitter();

  /// The clauses of [transcript], in the order they were spoken.
  ///
  /// Splits on the connectives people string tasks together with, and on a new
  /// leading temporal anchor ("… to James Friday check the App Store"), then
  /// undoes any split that produced a fragment which is not a task.
  List<String> splitClauses(String transcript) => <String>[
    for (final SplitClause clause in split(transcript)) clause.text,
  ];

  /// [splitClauses], each clause with the joint it was said after — which
  /// the extractor needs to carry a day from one task to the next: "Buy a
  /// cake on Saturday and order balloons" is two things for Saturday, "Buy a
  /// cake on Saturday, then later today order balloons" is not.
  List<SplitClause> split(String transcript) {
    final String text = transcript
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAllMapped(_stutter, (Match m) => m[1] ?? m[2] ?? m[3]!)
        // "And by the way, get the tyres changed" — an afterthought, the "oh"
        // of "Oh, and…": something new, not more of the task before. ⚠️
        // Kept, it was a card of its own, "By the way".
        .replaceAllMapped(
          _byTheWay,
          (Match m) => '${m[1]}${m[2] == 'B' ? 'Oh' : 'oh'}',
        )
        .replaceAllMapped(_danglingJoint, (Match m) => '${m[1]}, ');
    if (text.isEmpty) return const <SplitClause>[];
    final List<SplitClause> clauses = <SplitClause>[];
    final List<String> sentences = _toppedSentences(
      _selfCorrected(_sentences(text)),
    );
    for (final String sentence in sentences) {
      final List<String> joints = <String>[];
      final List<String> parts = _rejoin(
        _frontedWhens(_splitOnAnchors(_splitOnConnectives(sentence))),
        joints,
      );
      // A sentence opens after a stop — or, when it opens with "And", "Then"
      // or "After that", goes on with the one before it: "Call the plumber
      // tomorrow at 2pm. And text Bekzod the address." is how whisper writes
      // the comma it heard as a pause.
      if (joints.isNotEmpty) {
        joints[0] = clauses.isEmpty
            ? SplitClause.start
            : _sentenceJoint(sentence);
      }
      // ⚠️ An aside dropped from the end ("…for plov, you know.") must not
      // take the full stop with it: the extractor reads the stop as the end
      // of the sentence, and the day being talked about ends there.
      final Match? stop = _terminalStop.firstMatch(sentence);
      if (stop != null &&
          parts.isNotEmpty &&
          !_terminalStop.hasMatch(parts.last)) {
        parts.add('${parts.removeLast()}${stop[0]}');
      }
      // ⚠️ …and the reverse: "On Friday I have the dentist at 11 a.m., after
      // that…" leaves a clause ending in a full stop that ends nothing. Read
      // as the end of the sentence, it cut Friday off from the tasks after it.
      for (int i = 0; i < parts.length - 1; i++) {
        parts[i] = parts[i].replaceFirst(_abbreviationStop, '');
      }
      for (int i = 0; i < parts.length; i++) {
        clauses.add(SplitClause(parts[i], joints[i]));
      }
    }
    return clauses;
  }

  /// How [sentence] joins the one before it: "And …" → "and", "Then …" →
  /// "then", "And after that, …" → "after that", anything else a stop.
  ///
  /// ⚠️ Not "Oh, and …": an afterthought, which starts something new.
  static String _sentenceJoint(String sentence) {
    final RegExpMatch? m = _openingJoint.firstMatch(foldTemporalCase(sentence));
    if (m == null) return SplitClause.stop;
    if (m[2] != null || m[4] != null) return 'after that';
    if (m[3] != null) return 'and then';
    if (m[5] != null) return 'then';
    return SplitClause.and;
  }

  /// "by the way" where it opens what is said next: after a stop or a
  /// comma, after "and", "oh", "so", "but", "also".
  static final RegExp _byTheWay = RegExp(
    r'(^|[.,!?;]\s*|\b(?:[Aa]nd|[Oo]h|[Ss]o|[Bb]ut|[Aa]lso|[Uu]m|[Uu]h)[\s,]+)'
    r'([Bb])y the way\b',
  );

  /// "…call my brother Jamshid and. Uh. Transfer him the money": the "and"
  /// whisper ended a sentence with, and the hesitation it wrote as one of its
  /// own. ⚠️ Read as two stops, the transfer lost the day of the call.
  static final RegExp _danglingJoint = RegExp(
    r'\b(and then|and|then)[.!]+\s+'
    '(?:(?:${ClauseLexicon.hesitations})[.,!]*\\s+)*(?=\\S)',
    caseSensitive: false,
  );

  /// "And", "Then", "And then", "After that", "And after that" — with any
  /// hesitation in front — opening a sentence.
  static final RegExp _openingJoint = RegExp(
    '^[\\s,]*(?:(?:${ClauseLexicon.hesitations})[\\s,]+)*'
    r'(?:(and)\b(?:[\s,]+(?:(after\s+that|afterwards)|(then))\b)?'
    r'|(?:(after\s+that|afterwards)|(then))\b)',
  );

  /// A word said twice while the speaker thinks: "tomorrow at, at 10", "Ah,
  /// and, and one more thing", "I I need to" — and the same word three times
  /// over, which is a whisper loop, never a list.
  ///
  /// ⚠️ Kept, the first "at" was left over when the time was cut — "Call the
  /// plumber at, about the leak". Only the little words, though: a word a
  /// list may repeat is an item and the next one ("chocolate, chocolate milk",
  /// "paper, paper towels"), and was collapsed into one. Not "in", "on" or
  /// "by" either, which end a verb as often as they start a when: "check in
  /// in the morning" was "Check at the hotel", "stop by by 5" would be "Stop".
  /// And "had had" and "that that" are English.
  static final RegExp _stutter = RegExp(
    r"(?<![\w'-])(at|to|for|with|about|from|the|a|an|and|or|but|so|then|i|we"
    r"|my|today|tomorrow|tonight)(?:,\s*\1(?![\w'-]))+"
    // "Tomorrow tomorrow I have to…" — ⚠️ only one was cut from the title.
    r"|(?<![\w'-])(at|to|for|the|a|an|and|i|we|my|today|tomorrow|tonight)"
    r"(?:\s+\2(?![\w'-]))+"
    r"|(?<![\w'-])([a-z']+)(?:,\s*\3(?![\w'-])){2,}",
    caseSensitive: false,
  );

  // ── Pass 0: sentences ──────────────────────────────────────────────────────

  /// whisper punctuates, and a full stop is the strongest boundary a spoken
  /// list has: "I have some tasks. Today go to the bank." is two sentences,
  /// and the first is not a task at all.
  ///
  /// ⚠️ Not after "a.m."/"p.m." or a title like "Dr." — "at 5 p.m. call Anna"
  /// is one clause. And a sentence with nothing in it but when-words ("Buy
  /// milk. Tomorrow.") is folded back into the one before it.
  List<String> _sentences(String text) {
    final List<String> out = <String>[];
    int cursor = 0;
    for (final RegExpMatch match in _sentenceEnd.allMatches(text)) {
      final String before = text.substring(cursor, match.start + 1).trim();
      final String lastWord = before
          .split(' ')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'[.!?:]+$'), '');
      final bool nextIsCapital =
          match.end < text.length && RegExp(r'[A-Z]').hasMatch(text[match.end]);
      final bool isColon = match[0]!.trimRight().endsWith(':');
      if (!isColon) {
        // ⚠️ Before the initialism check: "p.m" has the shape of "u.s".
        // "9am" and "10.30pm" too, as whisper writes them: "…and on October
        // 7th at 9am. I have a job interview" is one clause, the interview at
        // 9 — broken there, the 9am went to the task before it.
        if (_softNoBreakAfter.contains(lastWord) ||
            _clockWithMeridiem.hasMatch(lastWord)) {
          // "Buy milk at 5 p.m. Call Anna at 7." is two sentences — whisper
          // capitalises the next one. "At 5 p.m. call Anna" is one, and so is
          // "At 5 p.m. Call Anna": a sentence that is only a time is glued to
          // the task it introduces.
          // ⚠️ Nor "…, and on October 7th at 9 a.m. I have an interview":
          // the time opens the clause after it, however the sentence began.
          if (!nextIsCapital ||
              _isWhenOnly(before) ||
              _isWhenOnly(_lastPart(before))) {
            continue;
          }
        } else if (_noBreakAfter.contains(lastWord) ||
            // "Call the U.S. embassy" — an initialism is not a sentence end.
            RegExp(r'^[a-z](?:\.[a-z])+$').hasMatch(lastWord)) {
          continue;
        }
      }
      if (before.isNotEmpty) out.add(before);
      cursor = match.end;
    }
    final String tail = text.substring(cursor).trim();
    if (tail.isNotEmpty) out.add(tail);

    final List<String> merged = <String>[];
    for (int i = 0; i < out.length; i++) {
      final String sentence = out[i];
      // "Buy milk. Tomorrow." folds back; "Tomorrow: buy milk" is a heading
      // for what follows and stays on its own.
      if (merged.isNotEmpty &&
          _isWhenOnly(sentence) &&
          !sentence.trimRight().endsWith(':')) {
        merged.add('${merged.removeLast()} $sentence');
      } else if (merged.isNotEmpty &&
          _saysMoreAboutTask(sentence) &&
          _refersBack(sentence, merged.last) &&
          _endsWithFullStop(merged.last) &&
          !NonTask.isNonTask(merged.last)) {
        merged.add(
          '${merged.removeLast().replaceFirst(_terminalStop, '')}, '
          '${_inLowerCase(sentence)}',
        );
      } else if (i + 1 < out.length &&
          _framesNext(sentence, out[i + 1]) &&
          _endsWithFullStop(sentence)) {
        out[i + 1] =
            '${sentence.replaceFirst(_terminalStop, '')}, ${out[i + 1]}';
      } else if (i + 1 < out.length &&
          _endsWithWhenForNext(sentence, out[i + 1])) {
        out[i + 1] =
            '${sentence.replaceFirst(_terminalStop, '')}, '
            '${_verbInLowerCase(out[i + 1])}';
      } else {
        merged.add(sentence);
      }
    }
    return merged;
  }

  /// Whether [sentence] only says more about the task before it — when it
  /// is, that it is due, how things stand with it: "It's due on the 25th.",
  /// "The flight is at 6 in the morning.", "The sale opens then.", "The
  /// samsa is inside."
  ///
  /// ⚠️ whisper hears the speaker's pause as a full stop, and said as a
  /// sentence of its own each was a card: "It's due", "The flight", "The
  /// sale opens". Joined back with the comma the speaker meant, the rules
  /// for "…, it's due on the 25th" read it. Not a person's news ("He is
  /// moving to Korea.") and not a task ("The car needs washing, do it
  /// tomorrow" opens with a thing, but goes on to a verb).
  bool _saysMoreAboutTask(String sentence) {
    final String folded = foldTemporalCase(sentence);
    final String body = folded.substring(_lead(folded).start);
    // "…print her homework. Do it tonight." — when to do the task before.
    final Match? doIt = _doItThen.matchAsPrefix(body);
    if (doIt != null) return _isWhenOnly(body.substring(doIt.end));
    if (!_statement.hasMatch(body) || NonTask.isAboutSomeoneElse(sentence)) {
      return false;
    }
    // A task after it — "…, so tomorrow pack the suitcase" — is fine: the
    // comma splits it off again. A verb inside the statement itself is not.
    final String statement = body
        .split(RegExp(r'[,;]|\b(?:and|so|then)\b'))
        .first;
    // With a when in it, only a deadline ("It's due on the 25th") or when
    // the thing itself is ("The flight is at 6"): "The bakery closes at 8",
    // "The trip is next week", "The weather is nice today" say something
    // else, and stay sentences of their own.
    if (_mentionsWhen(statement) &&
        !_dueOrAt.hasMatch(statement) &&
        !_dueOrAt.hasMatch(body)) {
      return false;
    }
    return !_words
        .allMatches(statement)
        .skip(1)
        .any(
          (RegExpMatch m) =>
              ClauseLexicon.isImperativeVerb(m[0]!) &&
              !_statementVerbs.contains(m[0]!),
        );
  }

  /// Whether [sentence] ends in "then" and a when only, and [next] is a
  /// task with no when of its own that opens with its verb: "…take my
  /// medicine, then tonight at 10. Send the report to Anna."
  ///
  /// ⚠️ whisper heard the pause after the when, not the one before it. Read
  /// where it put the stop, "then tonight at 10" went back onto the task
  /// before — the medicine at 10:00, with "then tonight" in its title — and
  /// the report had no when at all. Said with its own when ("…at 10. Call
  /// Anna at 5.") the next task is not the one the when is for; said after
  /// no "then" ("Buy milk. Tomorrow.") the when is the task's before it.
  bool _endsWithWhenForNext(String sentence, String next) {
    if (!_endsWithFullStop(sentence)) return false;
    final String folded = foldTemporalCase(sentence);
    RegExpMatch? then;
    for (final RegExpMatch m in _thenJoint.allMatches(folded)) {
      // "…until then tomorrow", "by then" — a when, not the next thing.
      if (_thenAsWhen.contains(wordBefore(folded, m.start + 1))) continue;
      then = m;
    }
    if (then == null || !_isWhenOnly(folded.substring(then.end))) return false;
    final String before = sentence.substring(0, then.start);
    if (!_isClause(before) && !_hasSubstance(before)) return false;
    final String after = foldTemporalCase(next);
    final String body = after.substring(_lead(after).start);
    final String head = wordAfter(body, 0);
    return (ClauseLexicon.isImperativeVerb(head) ||
            (ClauseLexicon.isLeadingOnlyVerb(head) &&
                _hasObject(body, head))) &&
        _isClause(body) &&
        !_saysAnyWhen(after);
  }

  /// "then", "and then", ", then" — said before a when.
  static final RegExp _thenJoint = RegExp(r'(?:,\s*|\s+)(?:and\s+)?then\s+');

  /// The words that make the "then" after them a when of its own.
  static const Set<String> _thenAsWhen = <String>{
    'until',
    'till',
    'til',
    'by',
    'since',
    'from',
    'before',
    'after',
    'back',
    'even',
    'only',
    'just',
    'right',
  };

  /// Whether any when at all is said in [folded]: a day, a clock time, a part
  /// of the day, "in two hours", "at some point".
  static bool _saysAnyWhen(String folded) =>
      DateGrammar.spans(folded).isNotEmpty ||
      TimeGrammar.allMatches(folded).isNotEmpty ||
      ClauseLexicon.vagueWhen.hasMatch(folded) ||
      _anchor.hasMatch(folded);

  /// [sentence] with its first word in lower case when that word is the verb
  /// it opens with: "Send the report" goes on after a comma as "send the
  /// report". A name stays as it is.
  static String _verbInLowerCase(String sentence) {
    final String head = wordAfter(sentence, 0);
    if (head.isEmpty) return sentence;
    final String folded = foldTemporalCase(head);
    if (!ClauseLexicon.isImperativeVerb(folded) &&
        !ClauseLexicon.isLeadingOnlyVerb(folded)) {
      return sentence;
    }
    final int at = sentence.indexOf(head);
    return '${sentence.substring(0, at)}$folded'
        '${sentence.substring(at + head.length)}';
  }

  static bool _refersBack(String sentence, String previous) {
    final String folded = foldTemporalCase(sentence);
    final Match? m = RegExp(
      r'^(?:the|its|my|our|their)\s+(?:[a-z]+\s+){0,2}?([a-z]+)\s+(?:is|are|was|were|opens|closes|starts|ends|came|comes|will)\b',
    ).firstMatch(folded.substring(_lead(folded).start));
    if (m == null) return true;
    final String prev = foldTemporalCase(previous);
    final String head = m[1]!;
    return prev.contains(head.length > 4 ? head.substring(0, 4) : head) ||
        TimeGrammar.allMatches(prev).isNotEmpty ||
        DateGrammar.spans(prev).isNotEmpty;
  }

  static final RegExp _doItThen = RegExp(r'do\s+(?:it|that|this)\b');

  /// "it's due…", "due on…", "the flight is at…", "it's at noon".
  static final RegExp _dueOrAt = RegExp(
    r"^(?:(?:it|this|that)(?:'s|\s+is|\s+was|\s+will\s+be)?\s+due|due"
    r'|(?:(?:the|its|his|her|my|our|their)\s+(?:[a-z]+\s+){0,2}?[a-z]+|it|that)'
    r"(?:\s+is|'s|\s+will\s+be|\s+starts)\s+(?:at|around|about|from))\b",
  );

  /// A thing and what it is or does — "it's…", "the flight is…", "the sale
  /// opens…", "due…" — at the start of a sentence.
  static final RegExp _statement = RegExp(
    r"^(?:(?:it|that|this)(?:'s|\s+is|\s+was|\s+will\s+be|\s+came|\s+comes"
    r'|\s+opens|\s+closes|\s+starts|\s+ends)'
    r'|(?:the|its|my|our|their)\s+(?:[a-z]+\s+){0,2}?[a-z]+\s+(?:is|are|was|were'
    r"|opens|closes|starts|ends|came|comes)|it's\s+due|due)\b",
  );

  /// The verbs a statement about a task says it with: "the sale starts",
  /// "the class ends", "it comes back".
  static const Set<String> _statementVerbs = <String>{'start', 'back'};

  /// [sentence] with its first word in lower case, as it reads after a
  /// comma: "It's due…", "The flight…". Not a name, not "I".
  static String _inLowerCase(String sentence) {
    final Match? first = RegExp(
      r"^(It|It's|That|This|The|Its|My|Our|Their"
      r'|Due|Do)\b',
    ).firstMatch(sentence);
    return first == null
        ? sentence
        : '${sentence[0].toLowerCase()}${sentence.substring(1)}';
  }

  static bool _endsWithFullStop(String sentence) =>
      RegExp(r'\.\s*$').hasMatch(sentence);

  /// Whether [sentence] is somebody else's plan with its day, and [next] the
  /// speaker's task about that person: "My sister is coming from Moscow on
  /// the 28th. I need to pick her up from the airport at 11 at night."
  ///
  /// ⚠️ Said with a comma, the plan's day frames the task after it; with the
  /// full stop whisper heard in the pause, the plan was a card of its own
  /// ("My sister is coming from Moscow") and the task lost nothing only by
  /// luck. Only when the task names the person again — "her", "him",
  /// "them" — which is what makes it an answer to the plan.
  bool _framesNext(String sentence, String next) {
    if (!NonTask.isAboutSomeoneElse(sentence)) return false;
    final String folded = foldTemporalCase(sentence);
    if (DateGrammar.spans(folded).isEmpty) return false;
    final String after = foldTemporalCase(next);
    if (!_isClause(after) || NonTask.isAboutSomeoneElse(after)) return false;
    return RegExp(r'\b(?:him|her|them)\b').hasMatch(after);
  }

  // ── Pass 0b: the speaker correcting themselves ─────────────────────────────

  /// [sentences] with the speaker's corrections applied, as a listener would
  /// write them down.
  ///
  /// "Call Sardor at 4, no wait, at 4.30" is a call at 4.30; "Take the lagman
  /// out. Uh, no, not lagman, the manti." is the manti. ⚠️ Left alone, the
  /// first time won and the second became a heading for the next task, and
  /// the correction became a card of its own.
  List<String> _selfCorrected(List<String> sentences) {
    final List<String> out = <String>[];
    for (final String raw in sentences) {
      final String sentence = _withoutRetractedWhen(raw);
      final RegExpMatch? swap = _notThisButThat.firstMatch(
        foldTemporalCase(sentence),
      );
      if (swap != null && out.isNotEmpty) {
        final String wrong = swap[1]!.trim();
        // The group is the last thing in the match, so its last occurrence.
        final int from = swap.start + swap[0]!.lastIndexOf(swap[2]!);
        final String right = sentence.substring(from, from + swap[2]!.length);
        final String previous = out.last;
        final int at = foldTemporalCase(previous)
            .lastIndexOf(RegExp('\\b${RegExp.escape(wrong)}\\b'));
        if (at >= 0) {
          out
            ..removeLast()
            ..add(
              '${previous.substring(0, at)}$right'
              '${previous.substring(at + wrong.length)}',
            );
          continue;
        }
      }
      out.add(sentence);
    }
    return out;
  }

  /// [sentence] without a when the speaker took back: "at 4, no wait, at
  /// 4.30" → "at 4.30", "tomorrow, sorry, Friday" → "Friday".
  ///
  /// ⚠️ Every retraction in one scan, not one per scan. Removing one and
  /// re-parsing the whole sentence for the next grew with the cube of the
  /// input: 100 corrections in 5,000 characters took over a second.
  String _withoutRetractedWhen(String sentence) {
    String out = _correctedToBareHour(sentence);
    while (true) {
      final String folded = foldTemporalCase(out);
      final List<_Cut> cuts = <_Cut>[
        ..._retractions(<(int, int)>[
          for (final TimeMatch m in TimeGrammar.allMatches(folded))
            (m.start, m.end),
        ], folded),
        ..._retractions(DateGrammar.spans(folded), folded),
      ]..sort((_Cut a, _Cut b) => a.start.compareTo(b.start));
      if (cuts.isEmpty) return out;
      final StringBuffer kept = StringBuffer();
      int cursor = 0;
      for (final _Cut cut in cuts) {
        if (cut.start > cursor) kept.write(out.substring(cursor, cut.start));
        if (cut.start >= cursor) {
          kept.write(out.substring(cut.insertStart, cut.insertEnd));
        }
        if (cut.end > cursor) cursor = cut.end;
      }
      kept.write(out.substring(cursor));
      out = kept.toString();
    }
  }

  /// [sentence] with an "at" in front of the bare hour a clock time was
  /// corrected to: "at 5 actually make it 6", "at 10 no 11", "at five, sorry,
  /// six" — so that [_retractions] sees the hour said instead. ⚠️ Without it
  /// the first time stayed and the correction was in the title: "Call Aziza
  /// actually make it 6" at 17:00.
  ///
  /// Only where the result reads as a clock time: "at 5, no, 6 people" is not
  /// one, and gets no "at".
  static String _correctedToBareHour(String sentence) {
    String out = sentence;
    for (final TimeMatch time in TimeGrammar.allMatches(
      foldTemporalCase(sentence),
    ).toList().reversed) {
      final String folded = foldTemporalCase(out);
      final Match? retraction = _toBareHour.matchAsPrefix(folded, time.end);
      if (retraction == null) continue;
      final int at = retraction.end;
      // Read only what follows: the whole sentence again for every
      // correction doubled the time a long note took.
      final Match? words = _nextWords.matchAsPrefix(folded, at);
      final String said = 'at ${words![0]}';
      final bool reads = TimeGrammar.allMatches(said).any(
        (TimeMatch m) =>
            m.start == 0 && m.end > 3 && TimeGrammar.endsClockTime(said, m.end),
      );
      if (reads) out = '${out.substring(0, at)}at ${out.substring(at)}';
    }
    return out;
  }

  /// The hour and what follows it in the sentence, up to 60 characters:
  /// enough to tell "6 p.m." and "6, call Anna" from "6 people".
  static final RegExp _nextWords = RegExp(r'[^.!?]{0,60}');

  static final RegExp _toBareHour = RegExp(
    '[\\s,.;–—-]*(?:(?:${ClauseLexicon.hesitations}|oh)[\\s,.;–—-]+)*'
    r'(?:no|wait|sorry|actually|i\s+mean|or\s+rather|rather|make\s+(?:it|that))'
    r'(?:[\s,.;–—-]+(?:no|wait|sorry|actually|i\s+mean'
    '|${ClauseLexicon.hesitations}|make\\s+(?:it|that)))*'
    r'[\s,.;–—-]+'
    r'(?=(?:\d{1,2}(?:[:.]\d{2})?|one|two|three|four|five|six|seven|eight'
    r'|nine|ten|eleven|twelve)\b)',
  );

  /// The ranges of [folded] to replace — with nothing, or with the when said
  /// instead — from each when in [spans] up to the one that replaces it.
  ///
  /// Only the nearest when after each can replace it: any later one has the
  /// nearer one's words in between.
  static List<_Cut> _retractions(List<(int, int)> spans, String folded) {
    final List<(int, int)> byStart = <(int, int)>[...spans]
      ..sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
    final List<_Cut> cuts = <_Cut>[];
    int next = 0;
    for (final (int, int) first in byStart) {
      while (next < byStart.length && byStart[next].$1 < first.$2) {
        next++;
      }
      if (next >= byStart.length) break;
      final int second = byStart[next].$1;
      final String between = folded.substring(first.$2, second);
      if (_retraction.hasMatch(between)) {
        cuts.add(_Cut(first.$1, second));
        continue;
      }
      // "tomorrow I must go to the tax office, no wait, on Friday, and give
      // them the papers" — the task's own words between the when and the
      // one that replaces it. The new when takes the old one's place, where
      // it still opens the sentence for every task in it. ⚠️ Kept, both
      // whens stayed: the trip was tomorrow and titled "…, no wait, on
      // Friday". Only within one clause, and only a when that ends where it
      // is said: "tomorrow call Anna, no, on Friday call Bob" is two tasks.
      final int secondEnd = byStart[next].$2;
      final RegExpMatch? late = _lateRetraction.firstMatch(between);
      if (late != null &&
          !_clauseBreak.hasMatch(between.substring(0, late.start)) &&
          _whenEnds.hasMatch(folded.substring(secondEnd))) {
        cuts
          ..add(_Cut(first.$1, first.$2, insert: (second, secondEnd)))
          ..add(_Cut(first.$2 + late.start, secondEnd));
      }
    }
    return cuts;
  }

  /// [_retraction] after a comma, at the end of the words before a when.
  static final RegExp _lateRetraction = RegExp(
    ',[\\s,.;–—-]*(?:(?:${ClauseLexicon.hesitations}|oh)[\\s,.;–—-]+)*'
    r'(?:no|wait|sorry|actually|i\s+mean|or\s+rather|rather|make\s+(?:it|that))'
    r'(?:[\s,.;–—-]+(?:no|wait|sorry|actually|i\s+mean'
    '|${ClauseLexicon.hesitations}|make\\s+(?:it|that)))*'
    r'[\s,.;–—-]*$',
  );

  static final RegExp _clauseBreak = RegExp(
    r'[,;.!?]|\b(?:and|then|also|but|so|because|plus)\b',
  );

  static final RegExp _whenEnds = RegExp(r'^\s*(?:[,.;!?]|and\b|then\b|$)');

  /// What stands between a when and the one that replaces it: ", no wait, ",
  /// ", sorry, ", " — I mean — ".
  static final RegExp _retraction = RegExp(
    '^[\\s,.;–—-]*(?:(?:${ClauseLexicon.hesitations}|oh)[\\s,.;–—-]+)*'
    r'(?:no|wait|sorry|actually|i\s+mean|or\s+rather|rather|make\s+(?:it|that))'
    r'(?:[\s,.;–—-]+(?:no|wait|sorry|actually|i\s+mean'
    '|${ClauseLexicon.hesitations}|make\\s+(?:it|that)))*'
    r'[\s,.;–—-]*$',
  );

  /// "Uh, no, not lagman, the manti." — a sentence that only swaps one word
  /// of the sentence before it for another.
  static final RegExp _notThisButThat = RegExp(
    '^(?:(?:${ClauseLexicon.hesitations}|oh|ah|sorry)[\\s,]+)*'
    r'no[\s,]+not\s+(?:the\s+|a\s+|an\s+)?'
    r"([a-z][a-z'\s-]{0,30}?)[\s,]+(?:but\s+|i\s+mean\s+)?"
    r"(?:the\s+|a\s+|an\s+)?([a-z][a-z'\s-]{0,30}?)[\s.!?]*$",
  );

  /// Nothing but a when: "Tomorrow.", "At six.", "In two hours."
  bool _isWhenOnly(String sentence) {
    final String folded = foldTemporalCase(sentence);
    final ({int start, bool whens}) lead = _lead(folded);
    return lead.whens && lead.start >= folded.length;
  }

  static final RegExp _terminalStop = RegExp(r'[.!?]+$');

  static final RegExp _abbreviationStop = RegExp(
    r'(?<=\b[ap]\.m|\betc)\.$',
    caseSensitive: false,
  );

  /// What follows the last connective in [text]: "at 9 a.m." in "…mortgage,
  /// and on October 7th at 9 a.m.".
  String _lastPart(String text) {
    final List<RegExpMatch> joints = _connective
        .allMatches(foldTemporalCase(text))
        .toList();
    return joints.isEmpty ? text : text.substring(joints.last.end);
  }

  static final RegExp _sentenceEnd = RegExp(r'(?:[.!?]+|:)\s+(?=\S)');

  /// "9am", "10.30pm", "7:15a.m" — a clock time whisper wrote with its am/pm
  /// run on: a full stop after it is soft, like one after "a.m".
  static final RegExp _clockWithMeridiem = RegExp(
    r'^\d{1,2}(?:[:.]\d{2})?(?:a\.?m|p\.?m)$',
  );

  /// A full stop after these usually is not the end of a sentence — unless
  /// the next word is capitalised.
  static const Set<String> _softNoBreakAfter = <String>{
    'a.m',
    'p.m',
    'am',
    'pm',
    'etc',
  };

  static const Set<String> _noBreakAfter = <String>{
    'mr',
    'mrs',
    'ms',
    'dr',
    'st',
    'vs',
    'e.g',
    'i.e',
  };

  // ── Pass 1: connectives ────────────────────────────────────────────────────

  List<_Fragment> _splitOnConnectives(String text) {
    final List<_Fragment> out = <_Fragment>[];
    final String folded = foldTemporalCase(text);
    // ⚠️ "in an hour and a half", "in two and a half hours" — an "and" inside
    // a when joins nothing. Split there, the task after it lost its time and
    // was glued onto the one before.
    final List<(int, int)> whens = <(int, int)>[
      ...DateGrammar.spans(folded),
      for (final TimeMatch m in TimeGrammar.allMatches(folded))
        (m.start, m.end),
    ];
    int cursor = 0;
    String pending = '';
    for (final RegExpMatch match in _connective.allMatches(folded)) {
      // The joint itself, without the spaces around it: the "so" of "in an
      // hour or so" is the last word of its when.
      final String said = match[0]!;
      final int jointStart =
          match.start + (said.length - said.trimLeft().length);
      final int jointEnd = match.end - (said.length - said.trimRight().length);
      if (whens.any(((int, int) w) => w.$1 < jointStart && jointEnd <= w.$2)) {
        continue;
      }
      // "I also need to call him" — an "also" right after its subject is an
      // adverb, not a joint between two tasks.
      final String joint = (match[1] ?? '').trim();
      if (joint == 'also' &&
          _alsoGlue.contains(wordBefore(folded, match.start))) {
        continue;
      }
      // "Finish the report before that meeting": a "that" of its own. Only
      // "…, before that buy a gift", "before that, call Anna" join two tasks.
      if (joint.startsWith('before') &&
          !RegExp(r'^\s*,').hasMatch(folded.substring(match.end)) &&
          !ClauseLexicon.isImperativeVerb(wordAfter(folded, match.end))) {
        continue;
      }
      // "It's raining so cancel the picnic" — "so" and "but" only join two
      // tasks when a task starts after them. "So, um, tomorrow…" does not.
      String separator = joint;
      if ((joint == 'so' || joint == 'but') &&
          !ClauseLexicon.isImperativeVerb(wordAfter(folded, match.end))) {
        // "…by train, so today I must buy the tickets": not a joint on its
        // own, but the comma in front of it still is a candidate boundary —
        // and so is the comma whisper left out before a "so" and a new day:
        // "…renew my driver's license so on Monday get new photos taken".
        if (!match[0]!.contains(',') &&
            !(joint == 'so' && _opensWithWhenThenTask(folded, match.end))) {
          continue;
        }
        separator = ',';
      }
      // "…on Monday I have to, uh, update my CV": the verb is still coming,
      // so the comma after "have to" joins nothing.
      if (_endsIncomplete(folded.substring(cursor, match.start))) continue;
      final String body = text.substring(cursor, match.start).trim();
      if (body.isNotEmpty) {
        out.add(_Fragment(separator: pending, text: body));
        pending = separator.isNotEmpty
            ? separator
            : (match[2] ?? match[3] ?? '').trim();
      } else if (out.isEmpty) {
        // "Also call Mark" — the connective opened the utterance.
        pending = '';
      }
      cursor = match.end;
    }
    final String tail = text.substring(cursor).trim();
    if (tail.isNotEmpty) out.add(_Fragment(separator: pending, text: tail));
    return out;
  }

  /// Whether the words from [from] open with a when and go on to a task: "on
  /// Monday get new photos", "this Sunday, write the first draft", "on
  /// Monday I have to update my CV" — not "so much", "so that…".
  bool _opensWithWhenThenTask(String folded, int from) {
    final int comma = folded.indexOf(RegExp(r'[,.;!?]'), from);
    final int end = comma < 0 || comma - from > 80 ? folded.length : comma;
    String rest = folded.substring(from, end > from + 80 ? from + 80 : end);
    final ({int start, bool whens}) lead = _lead(rest);
    if (!lead.whens) return false;
    if (lead.start >= rest.length) {
      // "…so this Sunday, write the first draft": the task is after the comma.
      if (comma < 0) return false;
      rest = folded.substring(comma + 1);
      return _opensWithVerb(rest.substring(_lead(rest).start));
    }
    final String body = rest.substring(lead.start);
    if (_opensWithVerb(body)) return true;
    final String head = wordAfter(body, 0);
    if (!_subjects.contains(head)) return false;
    final String afterSubject = body.substring(head.length);
    // "…so on Monday I have to up-make my CV": "I have to" says a task
    // follows, whatever whisper made of its verb. ⚠️ Only an obligation:
    // "so on Friday we can leave" says why, not what to do.
    final Match modal = _modal.matchAsPrefix(afterSubject)!;
    return RegExp(r"\b(?:to|must|should|need|will|'ll|gonna)\s*$")
        .hasMatch(afterSubject.substring(0, modal.end));
  }

  // ── Pass 2: a new leading temporal anchor ──────────────────────────────────

  List<_Fragment> _splitOnAnchors(List<_Fragment> fragments) {
    final List<_Fragment> out = <_Fragment>[];
    for (final _Fragment fragment in fragments) {
      final List<int> cuts = _anchorCuts(fragment.text);
      if (cuts.isEmpty) {
        out.add(fragment);
        continue;
      }
      int start = 0;
      for (final int cut in cuts) {
        final String body = fragment.text.substring(start, cut).trim();
        if (body.isNotEmpty) {
          out.add(
            _Fragment(
              separator: out.isEmpty || start == 0 ? fragment.separator : '',
              text: body,
            ),
          );
        }
        start = cut;
      }
      final String tail = fragment.text.substring(start).trim();
      if (tail.isNotEmpty) out.add(_Fragment(separator: '', text: tail));
    }
    return out;
  }

  /// Offsets inside [text] where a temporal anchor starts a new task.
  ///
  /// The anchor must not be the tail of the previous clause ("meet on Friday"),
  /// and it must be followed by a verb — which is what separates "buy milk
  /// tomorrow morning" (one task) from "… James Friday check the store" (two).
  List<int> _anchorCuts(String text) {
    final String folded = foldTemporalCase(text);
    final List<int> cuts = <int>[];
    for (final RegExpMatch match in _anchor.allMatches(folded)) {
      if (match.start == 0) continue;
      final String before = wordBefore(folded, match.start);
      if (_anchorGlue.contains(before)) continue;
      // "at 8 tonight check the logs": "tonight" qualifies the 8, it does not
      // start a new task after it.
      if (_timeWord.hasMatch(before)) continue;
      final Match? tail = _timeTail.matchAsPrefix(folded, match.end);
      final int after = tail?.end ?? match.end;
      if (!ClauseLexicon.isImperativeVerb(wordAfter(folded, after))) continue;
      cuts.add(match.start);
    }
    cuts.addAll(_onDateCuts(folded));
    return (cuts.toSet().toList())..sort();
  }

  /// Offsets in [folded] where "on" and a date start the next task: "…go to
  /// the dentist on October 5th pay the rent", the comma whisper left out
  /// before the "on".
  ///
  /// ⚠️ Only when the date is followed straight away by a verb a task starts
  /// with, and a task stands before the "on": "meet Anna on Friday at the
  /// cafe" and "book a table on Friday for dinner" are one task, on Friday.
  /// Read as one, the dentist's card took the rent and the milk in its title,
  /// on Monday. A time after the date ("…on the 5th at 9 pay…") could be
  /// either task's, so it cuts nothing.
  List<int> _onDateCuts(String folded) {
    final List<int> cuts = <int>[];
    final List<(int, int)> dates = DateGrammar.spans(folded);
    for (final RegExpMatch on in _onWord.allMatches(folded)) {
      if (on.start == 0) continue;
      // "…next week on Tuesday pay…" — one date, said in two parts.
      if (dates.any(
        ((int, int) span) => span.$1 < on.start && on.start < span.$2,
      )) {
        continue;
      }
      final int dayAt = _wordStart(folded, on.end);
      int end = -1;
      for (final (int, int) span in dates) {
        if ((span.$1 == on.start || span.$1 == dayAt) && span.$2 > end) {
          end = span.$2;
        }
      }
      if (end < 0) continue;
      final String rest = folded.substring(end);
      if (!RegExp(r'^\s+[a-z]').hasMatch(rest)) continue;
      if (!ClauseLexicon.isImperativeVerb(wordAfter(rest, 0))) continue;
      final String before = folded.substring(0, on.start).trimRight();
      if (!_isClause(rest) || !_isClause(before)) continue;
      // "We meet on Friday…", "leave on Monday…": the day is the verb's own.
      if (_opensWithVerb(wordBefore(before, before.length))) continue;
      // "Tell Anna on Friday bring the documents", "remind me on Monday call
      // the plumber": what the person is to do, not a task after theirs.
      if (_handsOver.hasMatch(before)) continue;
      // "Book the flight on Friday return on Sunday": the task after the
      // verb has a day of its own, so the Friday is not its day.
      if (_saysAnyWhen(rest)) continue;
      cuts.add(on.start);
    }
    return cuts;
  }

  static final RegExp _onWord = RegExp(r'\bon\b');

  /// "tell Anna", "ask my brother", "remind me" — at the end of the words
  /// before a when: the task that follows is theirs to do.
  static final RegExp _handsOver = RegExp(
    r"\b(?:tell|ask|remind|let|get|beg|help|teach)\s+(?:[a-z']+\s+){0,2}"
    r"[a-z']+$",
  );

  // ── Pass 2b: a when said on its own, in front of the task it is for ───────

  /// [fragments] with each when that stands alone between two tasks joined to
  /// the task after it: "…to the doctor, and on Friday afternoon, pick up her
  /// glasses" is the glasses on Friday afternoon.
  ///
  /// ⚠️ Left alone, the when had no verb, so [_rejoin] glued it onto the task
  /// BEFORE it — "Take the results to the doctor and on Friday" — and the
  /// glasses took the day of the doctor instead. Only a when followed by a
  /// comma and then a task: "Call Anna tomorrow, at 5, and buy milk" keeps
  /// its 5, and "…farewell party, at 7 p.m., he is moving to Korea" is the
  /// party's 7, not Korea's.
  List<_Fragment> _frontedWhens(List<_Fragment> fragments) {
    final List<_Fragment> out = <_Fragment>[];
    for (int i = 0; i < fragments.length; i++) {
      final _Fragment fragment = fragments[i];
      int next = i + 1;
      // "…, and on Friday, um, pick up…" — filler between says nothing.
      while (next < fragments.length &&
          fragments[next].separator == ',' &&
          _isFillerOnly(fragments[next].text)) {
        next++;
      }
      if (i == 0 ||
          next >= fragments.length ||
          fragments[next].separator != ',' ||
          !_isWhenOnly(fragment.text) ||
          !_isClause(fragments[next].text) ||
          NonTask.isNarration(fragments[next].text) ||
          NonTask.isAboutSomeoneElse(fragments[next].text)) {
        out.add(fragment);
        continue;
      }
      out.add(
        _Fragment(
          separator: fragment.separator,
          text: <String>[for (int j = i; j <= next; j++) fragments[j].text]
              .join(', '),
        ),
      );
      i = next;
    }
    return out;
  }

  // ── Pass 3: undo the splits that produced non-clauses ──────────────────────

  /// [joints] gets, for each clause returned, the connective said before
  /// it: "and", "then", ",", or nothing for the first.
  List<String> _rejoin(List<_Fragment> fragments, List<String> joints) {
    final List<String> clauses = <String>[];
    final StringBuffer current = StringBuffer();
    // The connective [current] was said after.
    String joint = '';
    void addClause(String clause) {
      clauses.add(clause);
      joints.add(joint);
    }

    // Filler between two tasks, held for the one after it, and the joint it
    // was said after.
    String carried = '';
    String carriedJoint = '';
    // The thing said first, for the tasks after it that say "it" or "them":
    // "The tickets, I need to buy them and send them to Aziz".
    String? topic;
    // Whether the condition that opens [current] already has its task.
    bool conditionMet = false;
    int at = -1;
    for (_Fragment fragment in fragments) {
      at++;
      if (current.isEmpty) {
        current.write(fragment.text);
        joint = fragment.separator;
        continue;
      }
      // "…about the car, oh and on Saturday…", "…for plov, you know." —
      // filler between two tasks is not part of the one before: glued on, it
      // ended up in a title, "Call Umid about the car, oh". It goes with the
      // one after, where the title cleaner drops it — and where an ordinal
      // still counts: "finish the deck, second, print it" is two tasks.
      if (_isFillerOnly(fragment.text)) {
        carried = '$carried${fragment.text}, ';
        // "…tomorrow and, um, pay the bill": the "and" said before the
        // filler is the joint of what follows it. ⚠️ Dropped, it left the
        // comma after the "um" as the joint, and the bill lost the day of the
        // task before it.
        if (carriedJoint.isEmpty && fragment.separator != ',') {
          carriedJoint = fragment.separator;
        }
        continue;
      }
      if (carried.isNotEmpty) {
        fragment = _Fragment(
          separator: fragment.separator == ',' && carriedJoint.isNotEmpty
              ? carriedJoint
              : fragment.separator,
          text: '$carried${fragment.text}',
        );
        carried = '';
        carriedJoint = '';
      }
      // "…because guests are coming": why, not what.
      if (fragment.separator == 'because') continue;
      final String sofar = current.toString();
      // "on the 1st pay the mortgage, on the 2nd the gas bill" — the verb is
      // said once and meant twice.
      final String? gapped =
          _gapped(sofar, fragment) ?? _gappedGoing(sofar, fragment);
      if (gapped != null) {
        fragment = _Fragment(separator: fragment.separator, text: gapped);
      }
      // "The car, I need to wash it on Sunday" — the thing said first, then
      // what to do with it.
      final ({String? done, String current, String? topic})? topical =
          fragment.separator == ','
          ? _withTopic(sofar, fragment.text, afterTopic: topic != null)
          : null;
      if (topical != null) {
        final String? done = topical.done;
        if (done != null) {
          addClause(done);
          joint = 'and';
        }
        current
          ..clear()
          ..write(topical.current);
        topic = topical.topic;
        conditionMet = false;
        continue;
      }
      // "My parents and my sister are coming on Sunday, clean the guest
      // room" — two who are coming. ⚠️ Split, "My parents" was a card and
      // the guest room lost Sunday.
      if (fragment.separator == 'and' &&
          !_isClause(sofar) &&
          NonTask.isAboutSomeoneElse('$sofar and ${fragment.text}')) {
        current
          ..write(_joiner(fragment.separator))
          ..write(fragment.text);
        continue;
      }
      // "…to the pharmacy, and remind me on Saturday to…" — a new request is
      // never the errand's purpose.
      final bool errand =
          fragment.separator == 'and' &&
          _isErrandTrip(sofar) &&
          !_subjects.contains(wordAfter(foldTemporalCase(fragment.text), 0)) &&
          !_newRequest.hasMatch(foldTemporalCase(fragment.text));
      // "When I get home, call mom" is one task with a condition, not two.
      // "Before 6 buy the cake" is a time, not a condition.
      // ⚠️ Nor is "After school pick up Max, buy bread": the task starts
      // right after "school", so the comma ends a task, not a condition —
      // glued, "pick up Max" was cut from the title with the condition.
      //
      // ⚠️ The condition takes one task, the first: "When I get home, call
      // mom, buy milk" is two — glued on, the milk was lost inside the call's
      // card. And a when that starts the task cuts nothing: "After work
      // tomorrow buy milk" was a card called "After work".
      final String sofarFolded = foldTemporalCase(sofar);
      final int sofarStart = _lead(sofarFolded).start;
      final bool subordinate =
          !conditionMet &&
          (fragment.separator == ',' || fragment.separator.isEmpty) &&
          _subordinator.hasMatch(sofarFolded.substring(sofarStart)) &&
          !opensWithEventThenTask(sofar.substring(sofarStart));
      // "Meeting at 10, lunch at 12, gym at 6" — two clock times cannot
      // belong to one task, whatever the words between them.
      final bool ownTime =
          fragment.separator == ',' &&
          TimeGrammar.firstMatch(foldTemporalCase(fragment.text)) != null &&
          TimeGrammar.firstMatch(foldTemporalCase(sofar)) != null &&
          !_datePhraseGoesOn(sofar, fragment.text);
      // "Tomorrow buy milk, tomorrow evening the laundry" — two items, each
      // opening with its own when, the second said without a verb. ⚠️ Glued,
      // the milk took the laundry's evening and the title both.
      final bool whenItem =
          (fragment.separator == ',' || fragment.separator == 'and') &&
          _lead(sofarFolded).whens &&
          _opensWithWhenThenThing(fragment.text);
      // "update my CV and print it", "print her homework, do it tonight" —
      // the same thing, said twice. "Tell Anna to call me and to bring the
      // keys" — one errand for Anna, however many things she is to do.
      final bool sameTask =
          _continuesPrevious(sofar, fragment) ||
          _continuesInstruction(sofar, fragment);
      // "…before 6, my husband is coming home early today" — somebody
      // else's day. Its own clause, for the extractor to read as context,
      // never glued into a title. So is the speaker's own: "Call Anna
      // tomorrow, and I'm free on Saturday, so clean the garage" — ⚠️ glued,
      // the garage lost Saturday, and "I'm free" stayed in Anna's title.
      final bool someoneElse =
          fragment.separator.isNotEmpty &&
          (NonTask.isAboutSomeoneElse(fragment.text) ||
              (NonTask.isSpeakerState(fragment.text) &&
                  _mentionsWhen(fragment.text)));
      // "Replied to Rustam's email and scheduled the team meeting for
      // Thursday at 11" — two things said as done, or whisper's "reply …
      // and schedule …": a card each, in the words said. ⚠️ Glued, the
      // meeting was lost inside the email's card. Only when the second has
      // a when of its own: "Called Anna and asked her about the party" is
      // one account of one call, and split it was two cards.
      final bool pastPair =
          fragment.separator == 'and' &&
          _opensWithPast(sofar) &&
          _opensWithPast(fragment.text) &&
          _hasOwnWhen(fragment.text);
      // "Call Shahnoza and Timur to invite them" — one more person to call.
      final bool purposeName =
          fragment.separator == 'and' && _namesPurpose(fragment.text);
      // "Tomorrow call the bank and once they approve the loan, sign the
      // papers" — the condition of the task after the comma, said before
      // it. ⚠️ Glued to the bank's card, the papers lost their condition
      // and took tomorrow. Only with that task after it.
      final String fragmentFolded = foldTemporalCase(fragment.text);
      final bool opensCondition =
          fragment.separator == 'and' &&
          at + 1 < fragments.length &&
          fragments[at + 1].separator == ',' &&
          _subordinator.hasMatch(
            fragmentFolded.substring(_lead(fragmentFolded).start),
          ) &&
          !_isClause(fragment.text) &&
          _isClause(sofar) &&
          _isClause(fragments[at + 1].text);
      // "…take my medicine, then tonight at 10 cent the report to Amma" —
      // "then" and a when open the next task, whatever whisper made of its
      // verb. ⚠️ Glued on, the medicine took the report into its title and
      // "at 10" as its time.
      final bool thenWhen =
          (fragment.separator == 'then' || fragment.separator == 'and then') &&
          _opensWithWhenThenUnknownVerb(fragment.text);
      final bool ownClause =
          (_isClause(fragment.text) && !purposeName) ||
          thenWhen ||
          ownTime ||
          someoneElse ||
          whenItem ||
          pastPair ||
          opensCondition;
      if (ownClause && !errand && !subordinate && !sameTask) {
        final String done = current.toString();
        current.clear();
        conditionMet = false;
        if ((_isClause(done) || _hasSubstance(done)) && !_isWhenOnly(done)) {
          addClause(done);
          joint = fragment.separator;
        } else {
          // "Okay, so first I need to finish…" — the "Okay" is not a task. It
          // rides along with the clause after it, where the title cleaner
          // strips it, rather than becoming a card of its own.
          current
            ..write(done)
            ..write(_joiner(fragment.separator));
        }
        // ⚠️ Only once it is a task of its own: "finish the report and
        // print it" is one task, and filled it would have become two.
        current.write(
          topic == null ? fragment.text : _filled(fragment.text, topic),
        );
      } else if ((NonTask.isNarration(fragment.text) || _isAside(fragment)) &&
          fragment.separator.isNotEmpty &&
          !_anchor.hasMatch(foldTemporalCase(fragment.text)) &&
          !_saysTaskTime(fragment.text)) {
        // "…to the mountains and we are jumping", "…my brother, it's his
        // birthday", "…the oven, the samsa is inside" — how things are, not
        // what to do. Dropped rather than glued onto the task's title.
        continue;
      } else {
        if (ownClause && subordinate) conditionMet = true;
        current
          ..write(_joiner(fragment.separator))
          ..write(fragment.text);
      }
    }
    if (current.isNotEmpty) addClause(current.toString());
    return clauses;
  }

  // ── The thing said first ───────────────────────────────────────────────

  /// [sofar] and [next] as one task when [sofar] only names the thing [next]
  /// is about: "The car, I need to wash it on Sunday" → "I need to wash the
  /// car on Sunday", "the car, I need to change the oil" → "the car: I need
  /// to change the oil". Null when it is not that shape.
  ///
  /// ⚠️ Uzbek puts the topic first, and so does English as its speakers
  /// learn it. Each such note was two cards: one holding only the noun, with
  /// no day, and one called "Wash it". Filler or small talk may come before
  /// the thing ("uh, the car, …"); a task may not — "Call Anna, the dentist,
  /// call them" keeps its call to Anna.
  ///
  /// Without a pronoun to fill, only one thing with a determiner, before "I
  /// need to…", "we have to…" or a verb — "The car, change the oil tomorrow"
  /// → "The car: change the oil tomorrow": "milk, eggs, bread, and call Anna"
  /// is a list and a task, and "Anna, call me" is somebody spoken to. Before
  /// a bare verb, not an event, which is a task of its own: "the dentist,
  /// call Anna".
  ///
  /// [afterTopic]: the task so far was itself about a thing said first, so
  /// "…, and the visa, I need to apply for it" is the next thing, in the same
  /// shape. Only then does a thing after an "and" start a task of its own —
  /// "call Anna and the plumber, I need to fix it" is one call.
  ({String? done, String current, String? topic})? _withTopic(
    String sofar,
    String next, {
    required bool afterTopic,
  }) {
    final String folded = foldTemporalCase(next);
    final int? pronoun = _fillablePronoun(folded);
    final String body = folded.substring(_lead(folded).start);
    final String head = wordAfter(body, 0);
    // "I need to…", "we have to…": the comment on a thing said first.
    final bool comment =
        _subjects.contains(head) &&
        _opensWithVerb(body.substring(head.length).replaceFirst(_modal, ''));
    // "…, change the oil": what to do about it, said straight.
    final bool order = !comment && _opensWithVerb(body);
    if (pronoun == null && !comment && !order) return null;

    String? done;
    String before = '';
    String topic;
    final RegExpMatch? and = afterTopic && pronoun != null && (comment || order)
        ? _andThenThing.firstMatch(sofar)
        : null;
    if (and != null && _isTopicPiece(and[2]!) && _isClause(and[1]!)) {
      // "…renew it, and the visa, I need to apply for it": the task before
      // the "and" is done, and the visa is the next thing.
      done = and[1]!.trim();
      topic = and[2]!.trim();
    } else {
      final List<String> pieces = sofar.split(',');
      int first = pieces.length;
      while (first > 0 && _isTopicPiece(pieces[first - 1])) {
        first--;
      }
      // "So the passport, …", "uh, the car, …" — filler in front of it.
      String opener = '';
      if (first > 0) {
        final String piece = pieces[first - 1];
        final int at = _lead(foldTemporalCase(piece)).start;
        if (at > 0 && at < piece.length && _isTopicPiece(piece.substring(at))) {
          opener = piece.substring(0, at).trim();
          pieces[first - 1] = piece.substring(at);
          first--;
        }
      }
      if (first == pieces.length) return null;
      before = <String>[
        pieces.take(first).join(',').trim(),
        opener,
      ].where((String p) => p.isNotEmpty).join(', ');
      if (before.isNotEmpty &&
          !_isFillerOnly(before) &&
          !_isWhenOnly(before) &&
          !NonTask.isNonTask(before)) {
        return null;
      }
      topic = pieces.skip(first).map((String p) => p.trim()).join(', ');
    }
    final String lead = before.isEmpty ? '' : '$before, ';
    if (pronoun != null) {
      if (!_topicFits(topic, folded, pronoun)) return null;
      // Said first, "The car" and "Milk, eggs" were capitalised only for
      // being first; "Mom" and "Anna, Timur" are names.
      if (_capitalOnlyForBeingFirst(topic, wordAfter(folded, pronoun))) {
        topic = '${topic[0].toLowerCase()}${topic.substring(1)}';
      }
      return (
        done: done,
        current: '$lead${_filled(next, topic, at: pronoun)}',
        topic: topic,
      );
    }
    final String topicFolded = foldTemporalCase(topic);
    final String determiner = wordAfter(topicFolded, 0);
    if (topic.contains(',') ||
        !_determiners.contains(determiner) ||
        (order &&
            _words
                .allMatches(topicFolded.substring(determiner.length))
                .any((RegExpMatch m) => ClauseLexicon.isEventNoun(m[0]!)))) {
      return null;
    }
    return (
      done: done,
      current: '$lead$topic: ${next.trimLeft()}',
      topic: null,
    );
  }

  /// "…the passport, and the visa" — a task, "and", and a thing.
  static final RegExp _andThenThing = RegExp(
    r'^(.*\S)\s*,?\s+and\s+([^,]+)$',
    caseSensitive: false,
  );

  /// [text] with [topic] in place of the pronoun at [at] — or, with none
  /// given, of its first "it" or "them" that is a verb's object.
  String _filled(String text, String topic, {int? at}) {
    final String folded = foldTemporalCase(text);
    final int? pronoun = at ?? _fillablePronoun(folded, thingsOnly: true);
    if (pronoun == null) return text;
    final int end = pronoun + wordAfter(folded, pronoun).length;
    return '${text.substring(0, pronoun)}$topic${text.substring(end)}';
  }

  /// Whether [topic] opens with a determiner, goes on in lower case after its
  /// first word, or is one word that [pronoun] calls a thing: "The car",
  /// "Milk, eggs, bread", "Kids, pick them up" — not "Mom, call her", "Anna,
  /// Timur".
  bool _capitalOnlyForBeingFirst(String topic, String pronoun) {
    final List<String> words = <String>[
      for (final RegExpMatch m in RegExp(
        r"[A-Za-z][A-Za-z']*",
      ).allMatches(topic))
        m[0]!,
    ];
    if (words.isEmpty) return false;
    final String first = words.first.toLowerCase();
    if (_determiners.contains(first) || first == 'this') return true;
    if (words.length == 1) return pronoun == 'it' || pronoun == 'them';
    return words
        .skip(1)
        .any((String w) => w != 'and' && w != 'or' && !_capital.hasMatch(w[0]));
  }

  /// "The car. I need to wash it on Sunday." — the thing as a sentence of its
  /// own, whisper having heard the pause as a full stop. Joined to the next
  /// sentence only when that one has a pronoun for it: "Milk. Eggs. Bread."
  /// is a list said slowly.
  List<String> _toppedSentences(List<String> said) {
    final List<String> sentences = <String>[...said];
    final List<String> out = <String>[];
    for (int i = 0; i < sentences.length; i++) {
      final String bare = sentences[i].replaceFirst(_terminalStop, '').trim();
      final String next = i + 1 < sentences.length
          ? foldTemporalCase(sentences[i + 1])
          : '';
      final int? pronoun = _fillablePronoun(next);
      if (pronoun != null &&
          bare.split(',').every(_isTopicPiece) &&
          _topicFits(bare, next, pronoun)) {
        sentences[i + 1] = '$bare, ${sentences[i + 1]}';
        continue;
      }
      out.add(sentences[i]);
    }
    return out;
  }

  /// Whether [piece] only names a thing: "the car", "my passport",
  /// "groceries", "Mom" — a determiner and up to three words, none of them a
  /// verb, a subject, a when or filler.
  bool _isTopicPiece(String piece) {
    final String folded = foldTemporalCase(piece).trim();
    if (folded.isEmpty ||
        _mentionsWhen(folded) ||
        _isFillerOnly(piece) ||
        NonTask.isNonTask(piece)) {
      return false;
    }
    final List<String> words = <String>[
      for (final RegExpMatch m in _words.allMatches(folded)) m[0]!,
    ];
    if (words.isEmpty || _opensWithVerb(words.first)) return false;
    final bool determined =
        _determiners.contains(words.first) || words.first == 'this';
    // "at home", "for Anna", "and then" say where or who, not what; "so the
    // passport" has filler in front, which the caller splits off.
    if (!determined && ClauseLexicon.isClauseHead(words.first)) return false;
    if (words.any(
      (String w) => w != 'and' && ClauseLexicon.isDiscourseWord(w),
    )) {
      return false;
    }
    final int count = words.length - (determined ? 1 : 0);
    return count >= 1 &&
        count <= 3 &&
        words
            .skip(determined ? 1 : 0)
            .every((String w) => !_notATopic.contains(w));
  }

  static const Set<String> _notATopic = <String>{
    'i',
    'we',
    'you',
    'he',
    'she',
    'they',
    'it',
    'me',
    'us',
    'him',
    'her',
    'them',
    'is',
    'are',
    'was',
    'were',
    'am',
    'be',
    "it's",
    "i'm",
    'will',
    'can',
    'should',
    'must',
    'need',
    'have',
    'has',
    'had',
    'to',
    'not',
    // "Now, send it to Anna", "Later, book it": when or how, not what.
    'now',
    'later',
    'again',
    'otherwise',
    'instead',
    'then',
    'here',
    'there',
    'too',
  };

  /// Whether [topic], said first, can be what the pronoun at [pronoun] in
  /// [next] stands for.
  ///
  /// ⚠️ A determiner ("the car", "my passport") or a list ("milk, eggs,
  /// bread") says it is a thing. A bare word may as well be a reaction or
  /// somebody spoken to — "Perfect, send it to Anna" was "Send perfect to
  /// Anna", "Timur, pick them up" was "Pick timur up" — so it must agree with
  /// the pronoun: a plural for "them" ("Groceries, buy them"), not one for
  /// "it" ("Rent, pay it"); "him" and "her" take names ("Mom, call her"). Not
  /// an adverb ("Seriously, send it"), and not when the task is for the
  /// speaker ("Anna, send it to me"): then the word is who is spoken to.
  bool _topicFits(String topic, String next, int pronoun) {
    final List<String> words = <String>[
      for (final RegExpMatch m in _words.allMatches(foldTemporalCase(topic)))
        m[0]!,
    ];
    if (words.isEmpty) return false;
    if (_determiners.contains(words.first) || words.first == 'this') {
      return true;
    }
    if (_forTheSpeaker.hasMatch(next)) return false;
    if (topic.contains(',') || words.length > 1) return true;
    final String word = words.single;
    if (word.endsWith('ly')) return false;
    return switch (wordAfter(next, pronoun)) {
      'them' => _looksPlural(word),
      'it' => !_looksPlural(word),
      _ => true,
    };
  }

  /// "…send it to me", "…call us back" — but not "remind me", which is the
  /// app being spoken to, whoever the task is for.
  static final RegExp _forTheSpeaker = RegExp(r'(?<!\bremind )\b(?:me|us)\b');

  /// Whether [word] looks like a noun in the plural: "kids", "groceries",
  /// "children" — not "glass", "bus", "Paris" or "Anna's".
  static bool _looksPlural(String word) =>
      _irregularPlurals.contains(word) ||
      (word.length >= 3 &&
          word.endsWith('s') &&
          !word.endsWith('ss') &&
          !word.endsWith('us') &&
          !word.endsWith('is') &&
          !word.endsWith("'s"));

  /// Where in [folded] an "it", "them", "him" or "her" stands for a thing
  /// named before — the object of a verb said earlier in the clause — or
  /// null. ⚠️ Not a possessive "her": in "pick up her kids" it is not Mom.
  ///
  /// [thingsOnly] leaves out "him" and "her": after the task the thing was
  /// named for, a person is somebody else.
  static int? _fillablePronoun(String folded, {bool thingsOnly = false}) {
    bool verbSeen = false;
    for (final RegExpMatch m in _words.allMatches(folded)) {
      final String word = m[0]!;
      if (_opensWithVerb(word)) {
        verbSeen = true;
        continue;
      }
      if (!verbSeen || !_objectPronouns.contains(word)) continue;
      if (thingsOnly && word != 'it' && word != 'them') continue;
      if (word == 'her') {
        final String after = wordAfter(folded, m.end);
        final bool object =
            after.isEmpty ||
            ClauseLexicon.isClauseHead(after) ||
            _particles.contains(after) ||
            _anchor.matchAsPrefix(folded, _wordStart(folded, m.end)) != null;
        if (!object) continue;
      }
      return m.start;
    }
    return null;
  }

  static const Set<String> _objectPronouns = <String>{
    'it',
    'them',
    'him',
    'her',
  };

  static const Set<String> _particles = <String>{
    'up',
    'back',
    'off',
    'out',
    'over',
    'in',
  };

  /// Whether [text] opens with "after"/"before" and the event it is about,
  /// then goes straight on to the task's verb: "After work buy milk, bread
  /// and eggs", "Before the trip on Friday pack the passport".
  ///
  /// ⚠️ That is a time for the task, not a condition clause ending at the
  /// first comma, as in "After I finish work, call mom": read as one, the
  /// verb and the first item went with it — "Bread and eggs" — or a whole
  /// task did. A subject ("after we land") or a name ("after Anna leaves")
  /// is a condition; so is anything with a comma before the verb.
  static bool opensWithEventThenTask(String text) =>
      eventTaskStart(text) != null;

  /// Where the task starts in [text] when [opensWithEventThenTask]: the verb
  /// of "After work buy milk", or the "I need to" of "After work I need to buy
  /// milk". Null when [text] is not that shape.
  ///
  /// The event is one or two words ("work", "the parent meeting", "5"),
  /// optionally with what it is with or where ("the meeting with Sardor",
  /// "the trip to Samarkand"), and whens may follow it ("the trip on
  /// Friday").
  ///
  /// ⚠️ Not "after the guests leave, wash the dishes": people in the plural
  /// and a bare verb are somebody doing something — a condition. Read as a
  /// time and a task, the condition was a card of its own, "After the guests
  /// leave". Only "classes", "meetings" — events in the plural — stay events.
  static int? eventTaskStart(String text) {
    // Only up to the first comma: one before the verb makes it a condition,
    // and a list after it is not worth reading — it grew with every item.
    final int comma = text.indexOf(',');
    final String folded = foldTemporalCase(
      comma < 0 ? text : text.substring(0, comma),
    );
    final Match? lead = _afterEvent.matchAsPrefix(folded);
    if (lead == null) return null;
    int at = lead.end;
    int nouns = 0;
    int complement = -1;
    for (int words = 0; words < 6; words++) {
      final String word = wordAfter(folded, at);
      if (word.isEmpty || _subjects.contains(word)) return null;
      final int start = folded.indexOf(word, at);
      if (words == 0 &&
          ((lead[1] == null && _capital.hasMatch(text[start])) ||
              _saysWhoActs(word))) {
        return null;
      }
      at = start + word.length;
      if (words > 0 && complement < 0 && _eventComplement.contains(word)) {
        // "the meeting with Sardor": the words after it are still the event.
        complement = 0;
        continue;
      }
      if (complement >= 0 ? ++complement > 3 : ++nouns > 2) return null;
      final int task = at + _lead(folded.substring(at)).start;
      final String rest = folded.substring(task);
      if (_opensWithVerb(rest)) return task;
      // "After work I need to buy milk": a subject and a modal before it.
      final String subject = wordAfter(rest, 0);
      if (_subjects.contains(subject)) {
        final String afterSubject = rest.substring(subject.length);
        final Match modal = _modal.matchAsPrefix(afterSubject)!;
        if (modal.end > 0 &&
            afterSubject.substring(0, modal.end).trim().isNotEmpty &&
            _opensWithVerb(afterSubject.substring(modal.end))) {
          return task;
        }
      }
    }
    return null;
  }

  static final RegExp _afterEvent = RegExp(
    r'\s*(?:after|before)\s+'
    r'((?:the|my|our|your|his|her|their|this|a|an)\s+)?',
  );

  /// What joins an event to who or what it is with: "the meeting with
  /// Sardor", "the trip to Samarkand", "the call at the bank".
  static const Set<String> _eventComplement = <String>{
    'with',
    'to',
    'at',
    'in',
    'of',
    'for',
    'from',
  };

  /// Whether [word] is a noun in the plural — "guests", "kids", "children" —
  /// which, with a bare verb after it, reads as that verb's subject: a
  /// condition. ⚠️ Not an event in the plural: "after classes pick up Max".
  /// "After the holidays buy new shoes, a coat…" reads as a condition too;
  /// the title cleaner still keeps its list whole.
  static bool _saysWhoActs(String word) {
    if (_irregularPlurals.contains(word)) return true;
    if (word.length < 4 || !_looksPlural(word)) return false;
    final String one = word.substring(0, word.length - 1);
    final String two = word.endsWith('es')
        ? word.substring(0, word.length - 2)
        : one;
    return !ClauseLexicon.isEventNoun(one) && !ClauseLexicon.isEventNoun(two);
  }

  static const Set<String> _irregularPlurals = <String>{
    'children',
    'people',
    'men',
    'women',
  };

  /// "go to the bazaar", "march down to the store" — a trip whose purpose is
  /// the clause after the "and". "Go to the bank and open an account" is one
  /// errand, not a card for the walk and another for the account.
  bool _isErrandTrip(String clause) {
    final String folded = foldTemporalCase(clause).replaceAll(',', ' ').trim();
    return _errandTrip.hasMatch(folded.substring(_lead(folded).start));
  }

  /// Whether [fragment] names a day or a time, in figures or in words.
  bool _hasOwnWhen(String fragment) =>
      _mentionsWhen(fragment) ||
      TimeGrammar.firstMatch(foldTemporalCase(fragment)) != null;

  bool _mentionsWhen(String fragment) {
    final String folded = foldTemporalCase(fragment);
    return _anchor.hasMatch(folded) || RegExp(r'\d').hasMatch(folded);
  }

  /// Whether the remark [fragment] says when the task itself is due or
  /// happens: "…, it's due at noon", "…, it's at 6".
  ///
  /// ⚠️ Only that shape keeps a remark's time. A time in any remark once
  /// counted, and a remark about something else's hours was glued into the
  /// title with its time: "Buy bread, the shop closes at noon" was a card
  /// "Buy bread, the shop closes" at 12:00, "Walk the dog tomorrow, it's too
  /// hot in the afternoon" one at 14:00 — and "the shop closes at 8" one at
  /// 08:00. A day in a remark still counts: "…, it's his birthday tomorrow".
  bool _saysTaskTime(String fragment) {
    final String folded = foldTemporalCase(fragment);
    return _dueOrAt.hasMatch(folded.substring(_lead(folded).start)) &&
        TimeGrammar.firstMatch(folded) != null;
  }

  /// Whether the comma between [sofar] and [next] sits inside one date
  /// phrase: "Dentist on Thursday morning, October 15th at 10".
  ///
  /// ⚠️ The "morning" read as a time of its own, so the rule against two times
  /// in one task cut the appointment at the comma: a card for Thursday morning
  /// and a junk card titled "October 15th at 10". Only a weekday's part of the
  /// day right before a date — "Pick up Max in the morning, Anna at 3" is two.
  bool _datePhraseGoesOn(String sofar, String next) =>
      _endsWithWeekdayPart.hasMatch(foldTemporalCase(sofar).trimRight()) &&
      _opensWithDate.hasMatch(foldTemporalCase(next));

  /// Words after which "also" is an adverb inside a clause: "I also need
  /// to…", "I'd also like to…", "you should also call…".
  static const Set<String> _alsoGlue = <String>{
    'i',
    'we',
    'you',
    'he',
    'she',
    'they',
    "i'd",
    "we'd",
    "you'd",
    "he'd",
    "she'd",
    "they'd",
    "i'll",
    "we'll",
    "you'll",
    'should',
    'would',
    'could',
    'will',
    'can',
    'must',
    'might',
    'may',
    'to',
    'said',
  };

  static const Set<String> _subjects = <String>{
    'i',
    'we',
    'you',
    'he',
    'she',
    'they',
  };

  static const Set<String> _determiners = <String>{
    'the',
    'a',
    'an',
    'my',
    'his',
    'her',
    'our',
    'their',
  };

  static final RegExp _subordinator = RegExp(
    r'^(?:when|once|if|as soon as|after|before|while|until|till|unless)\b',
  );

  static final RegExp _newRequest = RegExp(
    r"^(?:(?:um|uh|oh|so|also)\s+)*(?:remind|don't\s+forget|do\s+not\s+forget"
    r'|remember)\b',
  );

  static final RegExp _errandTrip = RegExp(
    r'^(?:(?:um|uh|so|okay|ok|well|first|then|also)\s+)*'
    // "after work go to Korzinka and buy eggs", "on the way home stop at…"
    r'(?:(?:after|before)\s+(?:the\s+|my\s+)?[a-z]+\s+'
    r'|on\s+the\s+way(?:\s+(?:home|back))?\s+)?'
    // ⚠️ "I am need to go to the bank and take money", "I am going to go
    // to…": without the "am", the trip was a card of its own with no day, and
    // the errand's day went to "Take money" alone.
    r"(?:(?:i|we)\s+)?(?:(?:am|are|'m|'re)\s+)?"
    // "I must to go to the tax office and give them the papers" too.
    r'(?:(?:need|have|want|got|going|must|should)(?:\s+to)?\s+'
    r"|will\s+|'ll\s+|gotta\s+|gonna\s+)?"
    r'(?:go|come|run|walk|drive|head|pop|swing|stop|march|nip|ride)'
    r'(?:\s+(?:down|over|up|out|back|by|round|across|quickly))?'
    // A trip that already has its purpose ("…and withdraw cash", "…for her
    // vitamins") is done: the next "and" starts a new task.
    r'\s+(?:to|by|into|at|in)\s+(?:(?!\band\b|\bfor\b)[^,;]){1,40}$',
  );

  /// Whether a fragment that is not a clause still says something worth a
  /// card: a when ("Tomorrow at 10 am interview with Google"), or any word
  /// that is not filler. "Okay", "So, um" and "Well" have none.
  bool _hasSubstance(String fragment) {
    final String folded = foldTemporalCase(fragment);
    return _words
        .allMatches(folded)
        .any((RegExpMatch m) => !ClauseLexicon.isFillerAt(folded, m.start));
  }

  /// Whether [fragment] can stand on its own as a task — for the title
  /// cleaner, which must not take the task after a comma for the start of
  /// one.
  static bool isClause(String fragment) =>
      const ClauseSplitter()._isClause(fragment);

  /// Whether [text] — "after the holidays buy new shoes" — has a verb that
  /// no subject pronoun comes before: a task, not only when to do one. "When
  /// I get home" has none.
  static bool ordersSomething(String text) {
    final String folded = foldTemporalCase(text);
    String before = '';
    for (final RegExpMatch m in _words.allMatches(folded)) {
      final String word = m[0]!;
      if (ClauseLexicon.isImperativeVerb(word) &&
          !_subjects.contains(before) &&
          before != 'to') {
        return true;
      }
      before = word;
    }
    return false;
  }

  /// Whether [fragment] can stand on its own as a task.
  ///
  /// ⚠️ This is the whole reason the splitter is not one `split(' and ')` call:
  /// "the release notes to James" has no verb of its own and opens with a
  /// determiner, so it belongs to the clause before it.
  bool _isClause(String fragment) {
    final String folded = foldTemporalCase(fragment)
        .replaceAll(',', ' ')
        .trim();
    // "second, print it" / "okay so first finish the deck": the ordinal and the
    // filler say nothing about whether a task follows. Nor does a when in
    // front — "on Friday check the mail" is a clause, and it is the "check"
    // behind the when that says so.
    final String body = folded.substring(_lead(folded).start).trim();
    if (body.isEmpty) return false;
    final String head = wordAfter(body, 0);
    if (ClauseLexicon.isEventNoun(head)) return true;
    // "sort the mail", "empty the bins" — but only as the opening word.
    if (ClauseLexicon.isLeadingOnlyVerb(head) && _hasObject(body, head)) {
      return true;
    }
    // "…and I'm calling Anna", "…and we're meeting the landlord".
    for (final RegExpMatch m in _progressive.allMatches(body)) {
      if (ClauseLexicon.progressiveVerb(m[1]!) != null) return true;
    }
    // "…and oh, the dentist for Max is on October 5th", "…there's a parent
    // meeting at school", "…we have a family dinner".
    if (_namesEvent(body)) return true;
    // "Remind me to call Nargiza at 4, to order the cake on Monday, and to buy
    // balloons" — each "to" is a task of the one "remind me".
    if (head == 'to' && _opensWithVerb(body.substring(head.length))) {
      return true;
    }
    // "…and on Sunday evening we play football", "…at 6 I pick up Zarina".
    if (_subjects.contains(head) &&
        _opensWithVerb(body.substring(head.length).replaceFirst(_modal, ''))) {
      return true;
    }
    if (ClauseLexicon.isClauseHead(head)) return false;
    // "Buy milk, water, and bread": a lone "water" is an item, not "water the
    // plants". A verb that opens the fragment needs something after it.
    if (ClauseLexicon.isImperativeVerb(head) && !_hasObject(body, head)) {
      return _words
          .allMatches(body.substring(head.length))
          .any((RegExpMatch m) => ClauseLexicon.isImperativeVerb(m[0]!));
    }
    return _words
        .allMatches(body)
        .any((RegExpMatch m) => ClauseLexicon.isImperativeVerb(m[0]!));
  }

  /// Whether [fragment], said after an "and", is a name and what it is for:
  /// "Timur to invite them to the wedding" after "call Shahnoza and", "uncle
  /// Rustam to confirm".
  ///
  /// ⚠️ The "to" names the purpose of the verb before, and the name is one
  /// more person for it. Read as a task because "invite" is a verb, it made
  /// "Call Shahnoza" and a junk "Timur to invite them". Only a name straight
  /// before the "to" — a capitalised word, or a title and a capitalised name
  /// — so that "Anna wants to…" and "Madina asked me to…" still say what
  /// someone did.
  ///
  /// ⚠️ A name, not any word: "buy milk, need to call Anna", "…and have to
  /// pick up Max", "time to call Anna" drop only the "I", and each is a task
  /// of its own — read as a name, it was glued onto the task before, "Buy
  /// milk, need to call Anna". And only after "and", the one word that adds
  /// a person to the verb: "Buy milk, Ali to pick up Max" is two things.
  bool _namesPurpose(String fragment) {
    // Same length as [folded], so its offsets hold for the capitals.
    final String said = fragment.replaceAll(',', ' ').trim();
    final String folded = foldTemporalCase(said);
    final Match? m = _namePurpose.matchAsPrefix(folded, _lead(folded).start);
    if (m == null || !_opensWithVerb(m[3]!)) return false;
    final String name = m[1]!;
    if (_subjects.contains(name) || _opensWithVerb(name)) return false;
    final String? second = m[2];
    final int at = second == null
        ? m.start
        : folded.indexOf(second, m.start + name.length);
    return _capital.hasMatch(said[at]);
  }

  static final RegExp _namePurpose = RegExp(
    r"([a-z']+)(?:\s+([a-z']+))?\s+to\s+([a-z]+)\b",
  );

  /// Whether [head] at the start of [body] is followed by a word that is not
  /// "and"/"or" — "water the plants", not "water and bread".
  bool _hasObject(String body, String head) {
    final String next = wordAfter(body, head.length);
    return next.isNotEmpty && next != 'and' && next != 'or';
  }

  /// "the dentist for Max", "the photo shoot", "there's a parent meeting",
  /// "we have the tax audit", "I have job interview at 11" — an event said
  /// without a verb.
  bool _namesEvent(String body) {
    final Match? have = _eventLead.matchAsPrefix(body);
    int at = have?.end ?? 0;
    final String first = wordAfter(body, at);
    if (_determiners.contains(first)) {
      at = body.indexOf(first, at) + first.length;
    } else if (have == null &&
        (ClauseLexicon.isClauseHead(first) ||
            ClauseLexicon.isImperativeVerb(first))) {
      return false;
    }
    final String one = wordAfter(body, at);
    final String two = wordAfter(body, body.indexOf(one, at) + one.length);
    return ClauseLexicon.isEventNoun(one) || ClauseLexicon.isEventNoun(two);
  }

  static final RegExp _eventLead = RegExp(
    r"(?:there(?:'s|\s+is|\s+are|\s+will\s+be)|(?:i|we)(?:\s+have|\s+have\s+got"
    r"|'ve\s+got|\s+got))\s+",
  );

  /// Whether [text] opens, past its filler and whens, with a past tense
  /// and what it was done to: "replied to Rustam's email", "scheduled the
  /// team meeting" — not "called, he said…".
  static bool _opensWithPast(String text) {
    final String folded = foldTemporalCase(text);
    final int start = _lead(folded).start;
    final String word = wordAfter(folded, start);
    if (!ClauseLexicon.isPastTense(word)) return false;
    final String next = wordAfter(
      folded,
      folded.indexOf(word, start) + word.length,
    );
    return next.isNotEmpty &&
        !_subjects.contains(next) &&
        !(word == 'got' && next == 'to');
  }

  static bool _opensWithVerb(String text) {
    final String word = wordAfter(text, 0);
    return ClauseLexicon.isImperativeVerb(word) ||
        ClauseLexicon.isLeadingOnlyVerb(word);
  }

  /// What stands between a subject and its verb: "we have to", "I will", "I
  /// must also".
  static final RegExp _modal = RegExp(
    r'^\s*(?:(?:also|really|just|still|then|probably|definitely)\s+)*'
    // "I am need to", "we are need": how people learning English say it.
    r'(?:(?:am|are|is)\s+need(?:\s+to)?'
    r'|(?:have|has|need|needs|want|got)\s+to|need|must|should|will|can'
    r'|could|would|wanna|gotta|gonna|(?:am|are)\s+going\s+to|going\s+to)?'
    r'(?:\s+(?:also|really|just|still|then))*\s*',
  );

  /// Where the task in [folded] — lower-cased by [foldTemporalCase] — starts:
  /// past the filler and the whens in front of it. See [_lead].
  static int taskStartIn(String folded) => _lead(folded).start;

  /// Where the task in [folded] starts: past the filler in front of it
  /// ("okay so", "um") and every when-phrase that opens it ("next week on
  /// Tuesday at noon", "the day after tomorrow", "in an hour and a half", "at
  /// some point"). [whens] says whether a when was passed.
  ///
  /// ⚠️ Asks the grammars rather than keeping a pattern of its own. The
  /// splitter used to, and every phrase that pattern lacked — "the day after
  /// tomorrow", "October 5th", "in two hours" — left a fragment that seemed to
  /// have no verb, so the task in it was glued onto the one before.
  static ({int start, bool whens}) _lead(String folded) {
    final List<(int, int)> spans = <(int, int)>[
      ...DateGrammar.spans(folded),
      for (final TimeMatch m in TimeGrammar.allMatches(folded))
        (m.start, m.end),
      for (final RegExpMatch m in ClauseLexicon.vagueWhen.allMatches(folded))
        (m.start, m.end),
    ];
    int cursor = 0;
    bool whens = false;
    while (true) {
      final int at = _wordStart(folded, cursor);
      if (at >= folded.length) return (start: folded.length, whens: whens);
      final String word = wordAfter(folded, at);
      int end = _spanEndAt(spans, at);
      // "on October 5th" — a preposition the grammar leaves outside.
      if (end < 0 && _whenPrepositions.contains(word)) {
        end = _spanEndAt(spans, _wordStart(folded, at + word.length));
      }
      if (end > at) {
        whens = true;
        cursor = end;
      } else if (ClauseLexicon.isFillerAt(folded, at) &&
          !ClauseLexicon.isClauseHead(word)) {
        cursor = at + word.length;
      } else {
        return (start: at, whens: whens);
      }
    }
  }

  static int _spanEndAt(List<(int, int)> spans, int start) {
    int end = -1;
    for (final (int, int) span in spans) {
      if (span.$1 == start && span.$2 > end) end = span.$2;
    }
    return end;
  }

  /// The first offset at or after [from] where a word starts.
  static int _wordStart(String text, int from) {
    int i = from;
    while (i < text.length && !_wordUnit.hasMatch(text[i])) {
      i++;
    }
    return i;
  }

  static final RegExp _wordUnit = RegExp(r"[a-z0-9'\u0080-\uffff]");

  static const Set<String> _whenPrepositions = <String>{
    'on',
    'at',
    'by',
    'in',
    'for',
    'from',
    'until',
    'till',
    'before',
    'after',
    'around',
    'about',
    'during',
  };

  /// "…, it's his birthday", "…, it came already", "…, the sale opens then",
  /// "…, the samsa is inside" — a remark about the task after a comma.
  ///
  /// ⚠️ A closed list of verbs after the subject, not "any word ending in
  /// -s": "…, the release notes" is an object, and "notes" would pass.
  bool _isAside(_Fragment fragment) =>
      fragment.separator == ',' &&
      !_isClause(fragment.text) &&
      _aside.hasMatch(foldTemporalCase(fragment.text));

  static final RegExp _aside = RegExp(
    r"^(?:(?:it|that|this|he|she|they)(?:'s|\s+is|\s+was|\s+came|\s+comes"
    r'|\s+has|\s+had|\s+opens|\s+closes|\s+starts|\s+ends)'
    r'|(?:the|my|his|her|our|their)\s+[a-z]+\s+(?:is|are|was|were|opens'
    r'|closes|starts|ends|came|comes))\b'
    // "the electricity bill, I forgot it again, pay it…" — about the thing
    // said first, between it and what to do. ⚠️ Kept, it cut the thing off
    // from its task: a card "The electricity bill, I forgot it again" and
    // one called "Pay it". Only the whole fragment: "I forgot to call Anna"
    // is a task.
    r'|^(?:i|we)\s+(?:(?:almost|totally|always|nearly)\s+)?'
    r'(?:forgot|forget|keep\s+forgetting)'
    r'(?:\s+(?:it|that|this|them|about\s+(?:it|that|this|them)))?'
    r'(?:\s+again)?\s*[.!]?$',
  );

  /// Whether [fragment] says nothing but filler: "oh", "um", "you know",
  /// "ah yes".
  bool _isFillerOnly(String fragment) {
    final String folded = foldTemporalCase(fragment)
        .replaceAll(_fillerPhrase, ' ');
    // ⚠️ By position, not by word: a fragment is what lies between two
    // commas, so a "like" alone in one is set off — "I have to, like, buy
    // milk" — and was a card titled "Like".
    return _words
        .allMatches(folded)
        .every((RegExpMatch m) => ClauseLexicon.isFillerAt(folded, m.start));
  }

  static final RegExp _fillerPhrase = RegExp(
    r'\b(?:you\s+know|i\s+mean|you\s+see|i\s+guess|i\s+think|yes)\b',
  );

  /// Whether [text] stops before its verb: "on Monday I have to", "I need
  /// to, uh".
  static bool _endsIncomplete(String text) {
    String t = text.replaceFirst(_trailingJunk, '');
    while (true) {
      final String last = wordBefore(t, t.length);
      // "…I have to, like" — the comma the caller split on sets it off.
      if (last.isEmpty ||
          !ClauseLexicon.isFillerAt(t, t.length - last.length) ||
          ClauseLexicon.isClauseHead(last)) {
        break;
      }
      t = t
          .substring(0, t.length - last.length)
          .replaceFirst(_trailingJunk, '');
    }
    return _incompleteTail.hasMatch(t);
  }

  static final RegExp _trailingJunk = RegExp(r'[\s,;]+$');

  static final RegExp _incompleteTail = RegExp(
    r'\b(?:(?:have|has|need|needs|got|want|going)\s+to|must|should|gonna'
    r"|wanna|gotta|remind\s+me\s+to|(?:i|we)\s+will|(?:i|we)'ll)$",
  );

  /// "update my CV and print it", "print her homework, do it tonight" — a verb
  /// whose object is the task before it. The same task, said twice.
  ///
  /// ⚠️ Not after an ordinal: "first finish the deck, second print it" is two
  /// tasks, counted out loud. Nor after "then", which orders two tasks. Nor
  /// after something that is not a task: in "the car insurance ends on
  /// Monday, renew it on Saturday" the renewal is the task, on Saturday.
  bool _continuesPrevious(String sofar, _Fragment fragment) {
    if (fragment.separator != 'and' && fragment.separator != ',') return false;
    if (!_isClause(sofar)) return false;
    final String folded = foldTemporalCase(fragment.text);
    if (_ordinal.hasMatch(folded)) return false;
    // "Did the laundry this morning, fold it tonight" — a thing done, then
    // what to do with it now: two. ⚠️ Glued, the folding went with the
    // laundry's morning, and a thing done that morning is no card at all.
    if (_opensWithPast(sofar) && !_opensWithPast(fragment.text)) return false;
    final String body = folded.substring(_lead(folded).start);
    final Match? match = _pronounObject.matchAsPrefix(body);
    if (match == null || !_opensWithVerb(match[1]!)) return false;
    final String rest = body
        .substring(match.end)
        .replaceAll(_afterthought, ' ');
    return rest.replaceAll(RegExp(r'[\s.!?,;]'), '').isEmpty ||
        _isWhenOnly(rest);
  }

  /// Whether [fragment] is one more "to + verb" of an instruction for
  /// somebody else in [sofar]: "…and to bring the keys" after "Tell Anna to
  /// call me".
  ///
  /// ⚠️ The "to + verb" rule in [_isClause] is for the speaker's own list —
  /// "remind me to call Nargiza, to order the cake, and to buy balloons".
  /// After "tell Anna to" or "ask Timur to" the next "to" is still Anna's.
  bool _continuesInstruction(String sofar, _Fragment fragment) {
    final String folded = foldTemporalCase(fragment.text);
    final String body = folded.substring(_lead(folded).start);
    if (wordAfter(body, 0) != 'to' || !_opensWithVerb(body.substring(2))) {
      return false;
    }
    final String prev = foldTemporalCase(sofar);
    RegExpMatch? last;
    for (final RegExpMatch m in _infinitive.allMatches(prev)) {
      if (_opensWithVerb(m[1]!)) last = m;
    }
    return last != null && _instructs.hasMatch(prev.substring(0, last.start));
  }

  static final RegExp _infinitive = RegExp(r'\bto\s+([a-z]+)');

  /// "tell Anna", "ask my brother", "remind Timur" — right before a "to":
  /// somebody other than the speaker is being given something to do.
  static final RegExp _instructs = RegExp(
    r'\b(?:tell|ask|remind|get|let|beg|help|teach|told|asked|reminded)\s+'
    r"(?!me\b|us\b)(?:[a-z']+\s+){0,2}[a-z']+\s*$",
  );

  static final RegExp _pronounObject = RegExp(
    r'([a-z]+)(?:\s+(?:up|off|out|back|over|in))?\s+(?:it|them)\b',
  );

  static final RegExp _ordinal = RegExp(
    r'\b(?:first|firstly|second|secondly|third|thirdly|next|finally|lastly)\b',
  );

  static final RegExp _afterthought = RegExp(
    r'\b(?:too|as\s+well|again|please)\b',
  );

  /// "on the 2nd the gas bill" after "on the 1st pay the mortgage" is "on the
  /// 2nd pay the gas bill": [fragment] with the verb of [sofar] put back, or
  /// null when it is not that shape.
  ///
  /// ⚠️ Only between two items that open with the same kind of when — "on
  /// the 1st …, on the 2nd …", "Monday …, Tuesday …" — which is what makes
  /// them a list. "Tomorrow buy milk, in the evening the laundry" does not
  /// mean buying the laundry.
  String? _gapped(String sofar, _Fragment fragment) {
    if (fragment.separator != ',' && fragment.separator != 'and') return null;
    final String folded = foldTemporalCase(fragment.text);
    final ({int start, bool whens}) lead = _lead(folded);
    if (!lead.whens || lead.start >= folded.length) return null;
    final String head = wordAfter(folded, lead.start);
    if (ClauseLexicon.isClauseHead(head) && !_determiners.contains(head)) {
      return null;
    }
    if (_isClause(fragment.text)) return null;
    final String prev = foldTemporalCase(sofar);
    final ({int start, bool whens}) prevLead = _lead(prev);
    if (!prevLead.whens || !_sameWhenShape(prev, folded)) return null;
    // ⚠️ A list names a different day each time: "on the 1st …, on the 2nd
    // …". "Tomorrow buy milk, tomorrow evening the laundry" names the same
    // day twice — the evening is when, not a second item to buy.
    if (_whenHead(prev) == _whenHead(folded)) return null;
    final Match? verb = _verbPhrase.matchAsPrefix(prev, prevLead.start);
    if (verb == null || !ClauseLexicon.isImperativeVerb(verb[1]!)) return null;
    return '${fragment.text.substring(0, lead.start)}'
        '${verb[0]!.trim()} ${fragment.text.substring(lead.start)}';
  }

  /// "go to the bank at 11 and then to the tax office" is "…and then go to
  /// the tax office": [fragment] with the going put back, or null when it is
  /// not a place said after one. ⚠️ Glued on, it was one card, "Go to the
  /// bank and then to the tax office", and the office had no day of its own.
  String? _gappedGoing(String sofar, _Fragment fragment) {
    // ⚠️ Only a next stop: "go to the gym and to the pool" is one trip.
    if (!fragment.separator.contains('then') &&
        !fragment.separator.contains('that')) {
      return null;
    }
    final String folded = foldTemporalCase(fragment.text);
    final int start = _lead(folded).start;
    if (_destination.matchAsPrefix(folded, start) == null) return null;
    final List<RegExpMatch> going = _going
        .allMatches(foldTemporalCase(sofar))
        .toList();
    if (going.isEmpty) return null;
    return '${fragment.text.substring(0, start)}${going.last[1]} '
        '${fragment.text.substring(start)}';
  }

  static final RegExp _going = RegExp(
    r'\b(go|drive|walk|head|run|come)\s+(?:back\s+|over\s+)?to\b',
  );

  static final RegExp _destination = RegExp(
    r'to\s+(?:the|my|our|his|her|their|a|an)\s+[a-z]',
  );

  /// Whether [fragment] opens with a when and goes on to a word in a verb's
  /// place — one with its object after it: "tonight at 10 cent the report to
  /// Amma", "tomorrow at 9 fax the documents to Bob".
  ///
  /// ⚠️ Not a subject, a pronoun, a copula or filler ("then tomorrow it
  /// rains", "then at 5 as well"), and not a name alone ("then tomorrow
  /// Anna"), which is who, not what to do.
  bool _opensWithWhenThenUnknownVerb(String fragment) {
    final String folded = foldTemporalCase(fragment);
    final ({int start, bool whens}) lead = _lead(folded);
    if (!lead.whens || lead.start >= folded.length) return false;
    final String head = wordAfter(folded, lead.start);
    if (!RegExp(r'^[a-z]{2,}$').hasMatch(head) ||
        // "then next week hopefully the mechanic fixes it" — how, not what.
        head.endsWith('ly') ||
        _capital.hasMatch(fragment[lead.start]) ||
        ClauseLexicon.isClauseHead(head) ||
        ClauseLexicon.isDiscourseWord(head) ||
        _subjects.contains(head) ||
        _notATopic.contains(head) ||
        _notAVerb.contains(head)) {
      return false;
    }
    final int headEnd = lead.start + head.length;
    if (RegExp(r'^\s*[,.;:!?]').hasMatch(folded.substring(headEnd))) {
      return false;
    }
    final String object = wordAfter(folded, headEnd);
    if (object.isEmpty) return false;
    final int objectAt = folded.indexOf(object, headEnd);
    return _verbObjects.contains(object) ||
        _capital.hasMatch(fragment[objectAt]);
  }

  /// Words that stand where a verb would and are none: "then tomorrow as
  /// well", "then at 5 maybe".
  static const Set<String> _notAVerb = <String>{
    'as',
    'maybe',
    'probably',
    'perhaps',
    'or',
    'if',
    'when',
    'because',
    'since',
    'no',
    'not',
    'yes',
    "it's",
    "that's",
    "there's",
    'everything',
    'everyone',
    'everybody',
    'something',
    'someone',
    'somebody',
    'anything',
    'anyone',
    'anybody',
    'nothing',
    'nobody',
  };

  /// What comes straight after a verb that has its object.
  static const Set<String> _verbObjects = <String>{
    'the',
    'a',
    'an',
    'my',
    'his',
    'her',
    'our',
    'their',
    'your',
    'this',
    'that',
    'these',
    'those',
    'some',
    'it',
    'them',
    'him',
    'me',
    'us',
  };

  /// Whether [fragment] opens with a when and goes on to name a thing: "tomorrow
  /// evening the laundry", "tomorrow at 6 Anna" — not "at 5 p.m. sharp".
  bool _opensWithWhenThenThing(String fragment) {
    final String folded = foldTemporalCase(fragment);
    final ({int start, bool whens}) lead = _lead(folded);
    if (!lead.whens || lead.start >= folded.length) return false;
    final String head = wordAfter(folded, lead.start);
    // A name: "Anna", "Sardor aka".
    return _determiners.contains(head) ||
        _capital.hasMatch(fragment[lead.start]);
  }

  static final RegExp _capital = RegExp('[A-Z]');

  /// Whether two whens open the same way: both "on …", or both a weekday.
  bool _sameWhenShape(String a, String b) {
    final String first = wordAfter(a, _wordStartAfterFiller(a));
    final String second = wordAfter(b, _wordStartAfterFiller(b));
    return first == second ||
        (_weekday.hasMatch(first) && _weekday.hasMatch(second));
  }

  /// The word a when turns on, past its preposition and article: "1st" in
  /// "on the 1st", "tuesday" in "next Tuesday", "tomorrow" in "tomorrow
  /// evening".
  static String _whenHead(String folded) {
    int at = _wordStartAfterFiller(folded);
    while (at < folded.length) {
      final String word = wordAfter(folded, at);
      if (!_whenPrepositions.contains(word) && !_whenArticles.contains(word)) {
        return word;
      }
      at = _wordStart(folded, at + word.length);
    }
    return '';
  }

  static const Set<String> _whenArticles = <String>{
    'the',
    'this',
    'next',
    'coming',
  };

  /// Where the first word that is not filler starts.
  static int _wordStartAfterFiller(String folded) {
    int at = _wordStart(folded, 0);
    while (at < folded.length) {
      final String word = wordAfter(folded, at);
      if (!ClauseLexicon.isFillerAt(folded, at) ||
          ClauseLexicon.isClauseHead(word)) {
        break;
      }
      at = _wordStart(folded, at + word.length);
    }
    return at;
  }

  static final RegExp _weekday = RegExp('^(?:$_weekdayWords)\$');

  static final RegExp _verbPhrase = RegExp(
    r'([a-z]+)(?:\s+(?:up|off|out|back|down))?\s',
  );

  static final RegExp _progressive = RegExp(
    r"\b(?:am|are|is|im|i'm|we're|you're|they're|he's|she's)\s+([a-z]+ing)\b",
  );

  String _joiner(String separator) {
    if (separator.isEmpty) return ' ';
    if (separator == ';') return '; ';
    if (separator == ',') return ', ';
    return ' $separator ';
  }

  // ── Patterns ───────────────────────────────────────────────────────────────

  static const String _weekdayWords =
      r'monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu'
      r'|friday|fri|saturday|sat|sunday|sun';

  static const String _monthWords =
      r'january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul'
      r'|august|aug|september|sept|sep|october|oct|november|nov|december|dec';

  static final RegExp _endsWithWeekdayPart = RegExp(
    '\\b(?:$_weekdayWords)\\s+(?:morning|afternoon|evening|night)\$',
  );

  /// "October 15th", "15 October", "the 15th" — a date at the very start.
  static final RegExp _opensWithDate = RegExp(
    '^(?:(?:$_monthWords)\\b'
    r'|the\s+\d{1,2}(?:st|nd|rd|th)\b'
    '|\\d{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?:$_monthWords)\\b)',
  );

  static final RegExp _words = RegExp(r"[a-z][a-z']*");

  static final RegExp _timeWord = RegExp(
    r'^(?:\d{1,2}(?:[:.]\d{2})?|[ap]\.?m\.?|am|pm|noon|midnight|one|two|three'
    r"|four|five|six|seven|eight|nine|ten|eleven|twelve|o'clock|oclock)$",
  );

  /// ⚠️ A bare comma is only a *candidate* boundary: `_rejoin` keeps the
  /// split only when what follows is a task of its own. "Buy eggs, milk and
  /// bread" stays one task; "check my email, reply to Aziz" becomes two.
  ///
  /// "because" is one only so that what follows it can be dropped: "buy rice
  /// for plov because guests are coming" is a reason, not part of the task.
  static final RegExp _connective = RegExp(
    r'\s*(?:,\s*)?\b(and\s+then|and\s+also|after\s+that|before\s+that|and'
    r'|also|then|plus'
    r'|so|but|because)\b\s*'
    r'|\s*(;)\s*'
    r'|\s*(,)\s*',
  );

  /// ⚠️ No leading preposition, unlike a when that opens a clause. "Meet Ana
  /// on Friday" ends a clause; "…to James Friday check the store" starts one.
  /// The preposition is the whole difference, so an anchor that has one is
  /// left for the clause it is already attached to.
  static final RegExp _anchor = RegExp(
    r'\b'
    r'(?:tomorrow|today|tonight|yesterday|'
    '(?:$_weekdayWords)'
    r'|next\s+week|next\s+month|the\s+weekend|weekend'
    r'|the\s+\d{1,2}(?:st|nd|rd|th))\b',
  );

  static final RegExp _timeTail = RegExp(
    r"(?:\s+(?:at|about|around|by|in|the|sharp|o'clock|noon|midnight|morning"
    r'|afternoon|evening|night|\d{1,2}(?::\d{2})?|[ap]\.?\s?m\.?))*',
  );

  /// Words that make the anchor behind them part of the clause that is already
  /// running: "send it on Friday" must not split before "Friday".
  static const Set<String> _anchorGlue = <String>{
    'on',
    'at',
    'by',
    'in',
    'for',
    'this',
    'next',
    'last',
    'until',
    'till',
    'til',
    'from',
    'before',
    'after',
    'since',
    'every',
    'coming',
    'and',
    'or',
    'of',
    'the',
    'a',
    'due',
    'starting',
    'is',
    'was',
    // "…, also later today return the drill"
    'later',
    'earlier',
  };
}

/// A range of a sentence to drop, and what of the same sentence, if
/// anything, to say in its place.
final class _Cut {
  _Cut(this.start, this.end, {(int, int) insert = (0, 0)})
    : insertStart = insert.$1,
      insertEnd = insert.$2;

  final int start;
  final int end;
  final int insertStart;
  final int insertEnd;
}

/// One clause of an utterance and the joint it was said after.
final class SplitClause {
  const SplitClause(this.text, this.joint);

  /// The first clause of the utterance.
  static const String start = '';

  /// The first clause of a sentence after a full stop.
  static const String stop = '.';

  /// "and", ", and" — and "And" opening a sentence, which goes on with the
  /// one before it.
  static const String and = 'and';

  final String text;

  /// The connective said before [text], lower-cased: [start], [stop],
  /// [and], "then", "and then", "after that", "also", "plus", "so", "but",
  /// ",", ";".
  final String joint;

  @override
  String toString() => joint.isEmpty ? text : '[$joint] $text';
}

final class _Fragment {
  const _Fragment({required this.separator, required this.text});

  /// The connective that introduced this fragment, kept verbatim so that
  /// undoing the split restores the original sentence.
  final String separator;
  final String text;
}
