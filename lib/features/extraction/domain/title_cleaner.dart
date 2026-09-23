import 'package:tasuke_ai/features/tasks/domain/task.dart';

import 'clause_splitter.dart';
import 'non_task.dart';
import 'time_grammar.dart';
import 'when_parser.dart';

/// Turns a spoken clause into the title the Confirm card shows.
///
/// "Tomorrow at 3 PM send the build to James" → "Send the build to James".
final class TitleCleaner {
  const TitleCleaner();

  /// Cuts the temporal span out of [clause] and tidies what is left.
  ///
  /// [spans] is what [ParsedWhen.spans] returned; when it is null the single
  /// [matchStart]..[matchEnd] range is cut instead.
  ///
  /// Idempotent by construction — `clean(clean(x)) == clean(x)` — because the
  /// Confirm screen re-cleans whatever the user typed back into the field.
  String clean(
    String clause, {
    required int matchStart,
    required int matchEnd,
    List<MatchSpan>? spans,
  }) {
    String text = _cut(
      clause,
      spans ?? <MatchSpan>[MatchSpan(matchStart, matchEnd)],
    );
    text = _withoutVagueWhen(text).replaceAll(_whitespace, ' ').trim();
    text = _withoutSetOffFiller(text);
    text = text.replaceAll(_strandedPunctuation, ' ').trim();

    // "The car: change the oil" — the thing the splitter found said first,
    // kept in front of what to do about it.
    String? topic;
    String previous = '';
    while (previous != text) {
      previous = text;
      text = text.replaceFirst(_leadingPunctuation, '').trimLeft();
      final Match? topicLead = topic == null
          ? _topicLead.matchAsPrefix(text)
          : null;
      if (topicLead != null) {
        topic = topicLead[1];
        text = text.substring(topicLead.end);
      }
      text = _dropLeadingSmallTalk(text);
      text = _dropSubordinateLead(text);
      text = _progressiveToImperative(text);
      text = text.replaceFirst(_whereIAm, '').trimLeft();
      text = text.replaceFirst(_thereIs, '').trimLeft();
      text = text.replaceFirst(_leadingFiller, '').trimLeft();
      text = text.replaceFirst(_leadingConnective, '').trimLeft();
      text = text.replaceFirst(_leadingDiscourse, '').trimLeft();
      text = text.replaceFirst(_haveAnEvent, '').trimLeft();
      text = _dropHaveBeforeEvent(text);
      text = _dropDanglingPreposition(text);
      text = text.replaceFirst(_leadingCopula, '').trimLeft();
      text = text.replaceFirst(_someoneAskedMe, '').trimLeft();
      text = text.replaceFirst(_reportedNeed, '').trimLeft();
      text = _dropDayToDo(text);
      text = _dropInfinitiveTo(text);
      text = _dropCallTo(text);
      text = _dropSubject(text);
      text = text.replaceFirst(_trailingRemnant, '').trimRight();
      text = text.replaceFirst(_appositiveOne, '').trimRight();
      text = text.replaceFirst(_trailingRescheduled, '').trimRight();
      text = text.replaceFirst(_trailingPreposition, '').trimRight();
      text = text.replaceFirst(_trailingPunctuation, '').trimRight();
    }

    if (topic != null) {
      final bool verbFirst = _isVerb(wordAfter(text.toLowerCase(), 0));
      text = text.isEmpty
          ? topic
          : '$topic: ${verbFirst ? _lowerFirst(text) : text}';
    }
    return TaskTitle.normalise(_sentenceCase(text));
  }

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : '${text[0].toLowerCase()}${text.substring(1)}';

  /// The thing [ClauseSplitter] put first with a colon: "the car: I need to
  /// change the oil".
  static final RegExp _topicLead = RegExp(
    r'((?:the|a|an|my|our|his|her|their|your|this)\s+[^:,.!?]{1,40}?):\s+',
    caseSensitive: false,
  );

  /// Removes [spans] from [clause], leaving a space behind so that the words
  /// either side of the cut do not fuse.
  ///
  /// Overlapping spans are cut as one: "the evening before" holds the
  /// "evening" the time came from, and cutting both in turn sliced the
  /// already-shortened text at the old offsets.
  ///
  /// An "every" or "each" in front of a span goes with it: "every Monday
  /// take out the trash" left "Every take out the trash".
  String _cut(String clause, List<MatchSpan> spans) {
    final List<MatchSpan> ordered =
        spans.where((MatchSpan s) => !s.isEmpty && s.start < clause.length).map(
            (MatchSpan s) {
              final int start = s.start.clamp(0, clause.length);
              final Match? every = _everyBefore.firstMatch(
                clause.substring(0, start),
              );
              return MatchSpan(
                every?.start ?? start,
                s.end.clamp(0, clause.length),
              );
            },
          ).toList()
          ..sort((MatchSpan a, MatchSpan b) => a.start.compareTo(b.start));
    final List<MatchSpan> merged = <MatchSpan>[];
    for (final MatchSpan span in ordered) {
      if (merged.isNotEmpty && span.start < merged.last.end) {
        final MatchSpan last = merged.removeLast();
        merged.add(
          MatchSpan(last.start, span.end > last.end ? span.end : last.end),
        );
      } else {
        merged.add(span);
      }
    }
    String out = clause;
    for (final MatchSpan span in merged.reversed) {
      if (span.isEmpty) continue;
      out = '${out.substring(0, span.start)} ${out.substring(span.end)}';
    }
    return out;
  }

  static final RegExp _everyBefore = RegExp(
    r'\b(?:every|each)\s+$',
    caseSensitive: false,
  );

  /// "I'm calling Anna" → "call Anna"; "I'm going to the dentist" → "go to the
  /// dentist"; "I'm going to call the bank" → "call the bank".
  String _progressiveToImperative(String text) {
    final Match? match = _progressiveLead.matchAsPrefix(text);
    if (match == null) return text;
    final String ing = match[1]!.toLowerCase();
    final String rest = text.substring(match.end);
    if (ing == 'going') {
      final Match? to = RegExp(
        r'to\s+',
        caseSensitive: false,
      ).matchAsPrefix(rest);
      if (to == null) return 'go $rest';
      final String after = rest.substring(to.end);
      return ClauseLexicon.isImperativeVerb(wordAfter(after.toLowerCase(), 0))
          ? after
          : 'go to $after';
    }
    final String? verb = ClauseLexicon.progressiveVerb(ing);
    return verb == null ? text : '$verb $rest';
  }

  static final RegExp _progressiveLead = RegExp(
    r"^(?:i['\u2019]m|i am|we['\u2019]re|we are|i['\u2019]ll be|we['\u2019]ll be)"
    r'\s+([a-z]+ing)\b\s*',
    caseSensitive: false,
  );

  /// "I'm at the dentist", "I'm on the night shift" → "dentist", "night
  /// shift".
  static final RegExp _whereIAm = RegExp(
    r"^(?:i['\u2019]m|i am|we['\u2019]re|we are)\s+(?:at|on|in)\s+"
    r'(?:the\s+|a\s+|an\s+|my\s+)?',
    caseSensitive: false,
  );

  /// "There's the board meeting" → "board meeting".
  static final RegExp _thereIs = RegExp(
    r"^(?:there['\u2019]s|there is|there will be|we have|i have)\s+"
    r'(?:the|a|an|my|our)\s+(?=\S)',
    caseSensitive: false,
  );

  static final RegExp _leadingPunctuation = RegExp(r'^[,;:–—-]+\s*');

  /// "When I get home, call mom" → "call mom". The condition is dropped from
  /// the title; the task is what goes on the list.
  ///
  /// ⚠️ Not "After work buy milk, bread and eggs": there the comma is inside
  /// the task, and cutting up to it left "Bread and eggs". Nor "after the
  /// holidays buy new shoes, a coat and a scarf", where what follows the
  /// comma is more of the list, not the task. "After work I need to buy
  /// milk" loses its "I need to" as a task said first would.
  String _dropSubordinateLead(String text) {
    final int? task = ClauseSplitter.eventTaskStart(text);
    if (task != null) {
      final String rest = text.substring(task);
      final String bare = rest.replaceFirst(_leadingFiller, '');
      return bare != rest && _isVerb(wordAfter(bare.toLowerCase(), 0))
          ? '${text.substring(0, task)}$bare'
          : text;
    }
    final Match? lead = _subordinateLead.matchAsPrefix(text);
    if (lead == null) return text;
    final String rest = text.substring(lead.end);
    if (ClauseSplitter.ordersSomething(text.substring(0, lead.end)) &&
        !ClauseSplitter.isClause(rest)) {
      return text;
    }
    return rest.trimLeft();
  }

  static final RegExp _subordinateLead = RegExp(
    r'^(?:when|once|as soon as|after|before|while|if)\b[^,]{1,60},\s*',
    caseSensitive: false,
  );

  /// "The meeting was moved (to Thursday at 3)" → "The meeting"; "the team
  /// meeting is starting (at 3 tomorrow)" → "The team meeting".
  static final RegExp _trailingRescheduled = RegExp(
    r'\s+(?:(?:was|is|has been|got|were|are|will be)\s+(?:moved|rescheduled'
    r'|changed|postponed|pushed|shifted|set|booked|planned|starting'
    r'|beginning|happening)|starts|begins)'
    r'(?:\s+(?:to|for|back|forward|until|till))?$',
    caseSensitive: false,
  );

  /// "I go to the market" → "Go to the market": a subject pronoun in front of
  /// a verb the task starts with.
  String _dropSubject(String text) {
    final Match? match = _subject.matchAsPrefix(text);
    if (match == null) return text;
    final String rest = text.substring(match.end);
    final String next = wordAfter(rest.toLowerCase(), 0);
    return _isVerb(next) || next == 'go' ? rest : text;
  }

  static bool _isVerb(String word) =>
      ClauseLexicon.isImperativeVerb(word) ||
      ClauseLexicon.isLeadingOnlyVerb(word);

  /// "whenever I have time fix the door" → "fix the door", "renew my library
  /// card, no rush" → "renew my library card". It said there is no date; it
  /// is not part of what to do.
  String _withoutVagueWhen(String text) {
    final List<RegExpMatch> found = ClauseLexicon.vagueWhen
        .allMatches(foldTemporalCase(text))
        .toList();
    String out = text;
    for (final RegExpMatch m in found.reversed) {
      out = '${out.substring(0, m.start)} ${out.substring(m.end)}';
    }
    return out;
  }

  /// "Call the plumber, uh, about the leak" → "Call the plumber about the
  /// leak": filler that commas set off, anywhere in the title.
  ///
  /// ⚠️ The leading-filler patterns only ever looked at the start, and the
  /// splitter hands a filler between two pieces of one task to the piece
  /// after it — so "uh", "like" and "you know" stayed in the middle of titles.
  /// Both commas go when the filler sits inside a phrase — after the verb
  /// ("Call, like, the bank") or before a preposition — and one stays when it
  /// may separate two items: "buy milk, uh, eggs and bread".
  String _withoutSetOffFiller(String text) =>
      text.replaceAllMapped(_setOffFiller, (Match m) {
        if (m.end >= text.length) return '';
        final String before = wordBefore(text, m.start).toLowerCase();
        final String after = wordAfter(text, m.end).toLowerCase();
        final bool inPhrase =
            _isVerb(before) ||
            before == 'to' ||
            _isVerb(after) ||
            _phraseGoesOn.contains(after);
        return inPhrase ? ' ' : ', ';
      });

  static final RegExp _setOffFiller = RegExp(
    '\\s*,\\s*(?:(?:${ClauseLexicon.hesitations}|like|you know)'
    '\\b\\s*(?:,\\s*|\$))+',
    caseSensitive: false,
  );

  static const Set<String> _phraseGoesOn = <String>{
    'about',
    'to',
    'for',
    'with',
    'at',
    'on',
    'in',
    'from',
    'by',
    'of',
    'into',
  };

  /// "Buy cat food, the one with the fish, the blue package" → "Buy cat
  /// food": a comma, then "the one" and what it is like — a description of
  /// the thing already named, however long it runs, never a new item. So is
  /// "the oat one", "the big blue one" at the end.
  static final RegExp _appositiveOne = RegExp(
    r'\s*,\s*(?:the|that)\s+(?:one\s+(?:with|that|which|who|from|in|on|for'
    r'|where|we|i|you|he|she|they|my|your|his|her|our|their)\b.*'
    r"|(?:[a-z'-]+\s+){1,2}one)$",
    caseSensitive: false,
  );

  /// "to order the cake" → "order the cake": one of the infinitives of a
  /// "remind me to …, to …, and to …".
  String _dropInfinitiveTo(String text) {
    final Match? match = _to.matchAsPrefix(text);
    if (match == null) return text;
    final String rest = text.substring(match.end);
    return _isVerb(wordAfter(rest.toLowerCase(), 0)) ? rest : text;
  }

  static final RegExp _to = RegExp(r'to\s+', caseSensitive: false);

  /// "I have call with the Tashkent office", "I have job interview at 11" —
  /// the article people learning English drop, which [_haveAnEvent] needs.
  String _dropHaveBeforeEvent(String text) {
    final Match? match = _have.matchAsPrefix(text);
    if (match == null) return text;
    final String rest = text.substring(match.end);
    final String lower = rest.toLowerCase();
    final String one = wordAfter(lower, 0);
    final String two = wordAfter(lower, lower.indexOf(one) + one.length);
    bool event(String w) => ClauseLexicon.isEventNoun(w) || w == 'call';
    return event(one) || event(two) ? rest : text;
  }

  static final RegExp _have = RegExp(
    r"(?:i|we)\s+(?:have|have got|['\u2019]ve got|got)\s+",
    caseSensitive: false,
  );

  /// "On I have a job interview" — the "on" of "on October 7th", left when
  /// the date was cut — and "Before send the report", the "before" of
  /// "before Friday".
  String _dropDanglingPreposition(String text) {
    final Match? pronoun = _danglingPreposition.matchAsPrefix(text);
    if (pronoun != null) return text.substring(pronoun.end).trimLeft();
    final Match? deadline = _danglingDeadline.matchAsPrefix(text);
    if (deadline == null) return text;
    final String rest = text.substring(deadline.end);
    return ClauseLexicon.isImperativeVerb(wordAfter(rest.toLowerCase(), 0))
        ? rest
        : text;
  }

  static final RegExp _danglingDeadline = RegExp(
    r'(?:before|after|by|until|till)\s+',
    caseSensitive: false,
  );

  static final RegExp _danglingPreposition = RegExp(
    r'^(?:on|at|by|in|from|until|till|before|after|for)\s+'
    r"(?=(?:i|we|you|there)(?:\b|['\u2019]))",
    caseSensitive: false,
  );

  /// "is Otabek's farewell party" — what is left of "the day after tomorrow
  /// is Otabek's farewell party".
  static final RegExp _leadingCopula = RegExp(
    r'^(?:is|are|was|were|will be)\s+(?=\S)',
    caseSensitive: false,
  );

  /// "Madina asked me to print her homework" → "print her homework": the
  /// errand is what follows the "to".
  ///
  /// ⚠️ Only after a subject — a name, "he", "my boss" — not "ask Anna who
  /// asked me to…", where the task is the asking.
  ///
  /// The subject may be gone already: "my mom called and asked me to buy
  /// bread" leaves "asked me to buy bread" once the report is dropped.
  static final RegExp _someoneAskedMe = RegExp(
    r"^(?:(?:(?:my|our|his|her|the)\s+[\w'\u2019]+|he|she|they"
    r"|[A-Z][\w'\u2019]*)\s+)?(?:asked|told|wants|wanted|needs|needed)\s+"
    r'(?:me|us)\s+to\s+',
  );

  /// "said I need to bring my passport" → "I need to bring my passport", which
  /// [_leadingFiller] then cuts to the errand: what is left of "the bank
  /// called and said I need to…" once the report before the "and" is gone.
  static final RegExp _reportedNeed = RegExp(
    r'^(?:(?:he|she|they|it)\s+)?(?:said|says|told\s+(?:me|us)|wrote|texted)'
    r'(?:\s+that)?\s+(?=(?:i|we)\s+(?:need|needed|have|had|must|should|got'
    r"|['\u2019]ve\s+got)\b)",
    caseSensitive: false,
  );

  /// "the last day to pay the parking fine" → "pay the parking fine": what is
  /// left of "today is the last day to…" once the day is cut. The task is the
  /// infinitive; the day is its date.
  String _dropDayToDo(String text) {
    final Match? match = _dayToDo.matchAsPrefix(text);
    if (match == null) return text;
    final String rest = text.substring(match.end);
    return _isVerb(wordAfter(rest.toLowerCase(), 0)) ? rest : text;
  }

  static final RegExp _dayToDo = RegExp(
    r'(?:the|my|our|your)\s+(?:(?:last|final|only)\s+)?'
    r'(?:day|chance|deadline|date|opportunity)\s+to\s+',
    caseSensitive: false,
  );

  /// "My god, I totally forgot, the car insurance…" → "the car insurance…":
  /// small talk said in front of the task, one comma-separated piece at a
  /// time. Only when something follows it — a title that is nothing but
  /// "Hello" is for [NonTask] to drop, not for this to empty.
  String _dropLeadingSmallTalk(String text) {
    final int comma = text.indexOf(',');
    if (comma <= 0) return text;
    final String rest = text.substring(comma + 1).trimLeft();
    if (rest.isEmpty || !NonTask.isNonTask(text.substring(0, comma))) {
      return text;
    }
    return rest;
  }

  /// "call to Gulnora" → "call Gulnora", as people learning English say it.
  /// ⚠️ Not "call to confirm the booking", where the "to" is the purpose.
  String _dropCallTo(String text) {
    final Match? match = _callTo.matchAsPrefix(text);
    if (match == null) return text;
    final String rest = text.substring(match.end);
    if (_isVerb(wordAfter(rest.toLowerCase(), 0))) return text;
    return '${match[1]} $rest';
  }

  static final RegExp _callTo = RegExp(
    r'(call|phone|ring|text)\s+to\s+',
    caseSensitive: false,
  );

  /// Upper-cases the first letter without touching the rest, so "send the
  /// build to James" keeps James.
  String _sentenceCase(String text) {
    if (text.isEmpty) return text;
    final String head = String.fromCharCode(text.runes.first);
    final String upper = head.toUpperCase();
    // ⚠️ Not every character upper-cases to one character — German ß becomes
    // SS — and growing the string here would silently lengthen every title.
    if (upper == head || upper.length != head.length) return text;
    return '$upper${text.substring(head.length)}';
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// What a cut leaves behind: " , ", " - ", stray brackets.
  static final RegExp _strandedPunctuation = RegExp(r'\s+[,;:–—-]+(?=\s|$)');

  /// The things people say before the task instead of the task.
  static final RegExp _leadingFiller = RegExp(
    r'^(?:please|remind me to|remind me|i need to|i needed to|i have to'
    r'|i gotta|do not forget to|make sure to|make sure you|make sure i'
    // "I should really start going to the gym" — ⚠️ matched as "i should"
    // alone, it was a card "Really start going to the gym".
    r'|i should(?: really| also| just| still)?|i must|i want to|lets'
    // "I also need to", "I really have to", "we still need to"
    r'|(?:i|we) (?:also|really|just|still|then|probably|definitely)'
    r' (?:need to|have to|must|should|want to|need)'
    // "I'd also like to", "you should also", "we would like to"
    r"|(?:i|we|you)(?:['\u2019]d| would| should| could| need to| have to"
    r'| must)(?: also| really| just| still)?(?: like to| love to| want to)?'
    r"|you['\u2019]ll need to|you need to|you have to"
    r"|don['\u2019]t forget to|don['\u2019]t forget|let['\u2019]s"
    r"|i need|i will|i['\u2019]ll|i am going to|i['\u2019]m going to"
    r"|i['\u2019]ve got to|i have got to|i got to|i would like to"
    r"|i['\u2019]d like to|we need to|we have to|we should|we must"
    r"|we will|we['\u2019]ll|gonna|remember to|i can|we can"
    // "I am need to call the bank", "we are need buy milk" — how people
    // learning English say it, and it stayed in the title whole.
    r"|(?:i am|i['\u2019]m|we are|we['\u2019]re) need(?: to)?"
    // "I have to, uh, update my CV"
    r')(?:[\s,]+|$)',
    caseSensitive: false,
  );

  /// "okay, so first", "um,", "second" — what comes before a list item.
  static final RegExp _leadingDiscourse = RegExp(
    '^(?:${ClauseLexicon.hesitations}'
    r'|okay|ok|so|well|alright|first|firstly|second'
    r'|secondly|third|thirdly|finally|lastly|next up|after that|oh yeah|oh'
    r'|yeah|anyway|actually|basically|i think|just|quickly|ah|ooh|wow'
    // "Maybe change the oil on Saturday": a hedge, not part of the errand.
    r'|maybe|perhaps|probably'
    // "…, now pack the bags": what is left to do, set against what is done.
    r'|now(?=[\s,]+[a-z])(?![\s,]+(?:that|is|was|it|i|we)\b)'
    // ⚠️ "like" only with its comma: "Like, buy eggs", not "like this".
    r'|like(?=\s*,)'
    // ⚠️ Not "listen to the podcast", where it is the task's verb.
    r'|honestly|listen(?!\s+to\b)|you know)\b[\s,.]*',
    caseSensitive: false,
  );

  /// "I have a meeting with Sardor" → "meeting with Sardor".
  static final RegExp _haveAnEvent = RegExp(
    r"^(?:i|we)\s+(?:have|have got|['\u2019]ve got|got)\s+(?:a|an)\s+",
    caseSensitive: false,
  );

  static final RegExp _subject = RegExp(r'^(?:i|we)\s+', caseSensitive: false);

  /// What is left of "…, it's due (on the 25th)" or "…, don't forget" once
  /// the when-words are cut.
  static final RegExp _trailingRemnant = RegExp(
    // "…for Bobik, both (on Friday)"
    r'(?:,\s*)(?:both(?:\s+of\s+them)?|(?:all|each)\s+of\s+(?:them|these))$'
    r"|(?:,\s*|\s+)(?:it['\u2019]?s|it is|which is|that is)(?:\s+due)?$"
    r"|(?:,\s*|\s+)(?:don['\u2019]t forget|please|ok|okay)$"
    // "change the oil on Saturday maybe": a hedge left behind by the day.
    r'|(?:,\s*|\s+)(?:maybe|probably|perhaps)$'
    // "print her homework, do it (tonight)"
    r'|(?:,\s*|\s+)(?:and\s+)?do\s+(?:it|that|this)$'
    r"|(?:,\s*|\s+)(?:and\s+)?(?:i think\s+)?that['\u2019]?s (?:it|all)"
    r'(?:\s+for\s+(?:now|today))?$',
    caseSensitive: false,
  );

  static final RegExp _leadingConnective = RegExp(
    r'^(?:and|then|also|plus|but|so)\b[\s,]*',
    caseSensitive: false,
  );

  /// A preposition left dangling by the cut — `send the build to <tomorrow>`.
  static final RegExp _trailingPreposition = RegExp(
    r'(?:^|\s)(?:at|on|in|by|for|to|with|from|until|till|of|about|around'
    r'|before|after|and|then|also|plus|the|a|an|this|next|my|your'
    // "water the plants every (Monday)"
    r'|every'
    // "…the dentist for Max is (on October 5th)"
    r'|is|are|was|were|will be)$',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuation = RegExp(r'[\s,;:.!–—-]+$');
}
