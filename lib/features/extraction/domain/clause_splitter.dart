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

  /// Words no task starts with. A fragment that opens with one of these is a
  /// continuation of the previous clause, not a new one.
  static bool isClauseHead(String word) => _heads.contains(word);

  static const Set<String> _verbs = <String>{
    'add',
    'apply',
    'arrange',
    'ask',
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
    'delete',
    'deliver',
    'deploy',
    'discuss',
    'draft',
    'drop',
    'email',
    'feed',
    'fetch',
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
    'install',
    'join',
    'make',
    'meet',
    'merge',
    'message',
    'move',
    'order',
    'organise',
    'organize',
    'pack',
    'pay',
    'pick',
    'practice',
    'practise',
    'prepare',
    'print',
    'read',
    'refill',
    'register',
    'remember',
    'remind',
    'renew',
    'reply',
    'reschedule',
    'research',
    'respond',
    'return',
    'review',
    'schedule',
    'send',
    'set',
    'share',
    'ship',
    'sign',
    'start',
    'study',
    'submit',
    'take',
    'talk',
    'tell',
    'test',
    'text',
    'transfer',
    'update',
    'upgrade',
    'upload',
    'visit',
    'walk',
    'wash',
    'water',
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
  List<String> splitClauses(String transcript) {
    final String text = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return const <String>[];
    return _rejoin(_splitOnAnchors(_splitOnConnectives(text)));
  }

  // ── Pass 1: connectives ────────────────────────────────────────────────────

  List<_Fragment> _splitOnConnectives(String text) {
    final List<_Fragment> out = <_Fragment>[];
    final String folded = foldTemporalCase(text);
    int cursor = 0;
    String pending = '';
    for (final RegExpMatch match in _connective.allMatches(folded)) {
      final String body = text.substring(cursor, match.start).trim();
      if (body.isNotEmpty) {
        out.add(_Fragment(separator: pending, text: body));
        pending = (match[1] ?? match[2] ?? '').trim();
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
      if (_anchorGlue.contains(wordBefore(folded, match.start))) continue;
      final Match? tail = _timeTail.matchAsPrefix(folded, match.end);
      final int after = tail?.end ?? match.end;
      if (!ClauseLexicon.isImperativeVerb(wordAfter(folded, after))) continue;
      cuts.add(match.start);
    }
    return cuts;
  }

  // ── Pass 3: undo the splits that produced non-clauses ──────────────────────

  List<String> _rejoin(List<_Fragment> fragments) {
    final List<String> clauses = <String>[];
    final StringBuffer current = StringBuffer();
    for (final _Fragment fragment in fragments) {
      if (current.isEmpty) {
        current.write(fragment.text);
        continue;
      }
      if (_isClause(fragment.text)) {
        clauses.add(current.toString());
        current.clear();
        current.write(fragment.text);
      } else {
        current
          ..write(_joiner(fragment.separator))
          ..write(fragment.text);
      }
    }
    if (current.isNotEmpty) clauses.add(current.toString());
    return clauses;
  }

  /// Whether [fragment] can stand on its own as a task.
  ///
  /// ⚠️ This is the whole reason the splitter is not one `split(' and ')` call:
  /// "the release notes to James" has no verb of its own and opens with a
  /// determiner, so it belongs to the clause before it.
  bool _isClause(String fragment) {
    final String folded = foldTemporalCase(fragment);
    // A leading anchor is not a head word — "on Friday check the mail" is a
    // clause, and it is the "check" behind the anchor that says so.
    final Match? anchor = _leadingAnchor.matchAsPrefix(folded);
    final String body = anchor == null
        ? folded
        : folded.substring(anchor.end).trim();
    if (body.isEmpty) return false;
    final String head = wordAfter(body, 0);
    if (ClauseLexicon.isClauseHead(head)) return false;
    return _words
        .allMatches(body)
        .any((RegExpMatch m) => ClauseLexicon.isImperativeVerb(m[0]!));
  }

  String _joiner(String separator) {
    if (separator.isEmpty) return ' ';
    if (separator == ';') return '; ';
    return ' $separator ';
  }

  // ── Patterns ───────────────────────────────────────────────────────────────

  static const String _weekdayWords =
      r'monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu'
      r'|friday|fri|saturday|sat|sunday|sun';

  static final RegExp _words = RegExp(r"[a-z][a-z']*");

  static final RegExp _connective = RegExp(
    r'\s*(?:,\s*)?\b(and\s+then|and\s+also|after\s+that|and|also|then|plus)\b\s*'
    r'|\s*(;)\s*',
  );

  /// ⚠️ No leading preposition, unlike [_leadingAnchor]. "Meet Ana on Friday"
  /// ends a clause; "…to James Friday check the store" starts one. The
  /// preposition is the whole difference, so an anchor that has one is left for
  /// the clause it is already attached to.
  static final RegExp _anchor = RegExp(
    r'\b'
    r'(?:tomorrow|today|tonight|yesterday|'
    '(?:$_weekdayWords)'
    r'|next\s+week|next\s+month|the\s+weekend|weekend'
    r'|the\s+\d{1,2}(?:st|nd|rd|th))\b',
  );

  static final RegExp _leadingAnchor = RegExp(
    r'(?:(?:on|by|at|in|this|next|last|coming)\s+)?'
    r'(?:tomorrow|today|tonight|yesterday|'
    '(?:$_weekdayWords)'
    r'|next\s+week|next\s+month|weekend|\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?'
    r'|the\s+\d{1,2}(?:st|nd|rd|th))\b'
    r"(?:\s+(?:at|about|around|by|in|the|sharp|o'clock|noon|midnight|morning"
    r'|afternoon|evening|night|\d{1,2}(?::\d{2})?|[ap]\.?\s?m\.?))*\s*',
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
  };
}

final class _Fragment {
  const _Fragment({required this.separator, required this.text});

  /// The connective that introduced this fragment, kept verbatim so that
  /// undoing the split restores the original sentence.
  final String separator;
  final String text;
}
