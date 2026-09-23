import 'clause_splitter.dart';

/// Recognises the things people say into a to-do app that are not to-dos.
///
/// ⚠️ Every one of these came back from a real capture as a task the user then
/// had to delete: "Hello, how are you?", "Thank you." (what whisper writes for
/// silence), "Let's go.", and above all the preamble — "I have some tasks for
/// today." — which people say before the list the way they would to a person.
///
/// Deliberately a short list of shapes, not a classifier. A false positive
/// here silently deletes something the user said, and the pipeline already
/// turns an empty result into one editable draft of the whole transcript, so
/// when in doubt the answer is "it is a task".
abstract final class NonTask {
  /// Whether [clause] as a whole is small talk, an acknowledgement or a
  /// preamble — something with nothing to do in it.
  static bool isNonTask(String clause) {
    if (_normalise(clause).isEmpty) return true;
    // "Thank you, that's all for now." / "Okay, so I have a few tasks for
    // today, let me think." — every piece has to be empty talk, not just one.
    // "Um, is this thing on?" — the "um" says nothing either way.
    final List<String> parts = clause
        .split(RegExp(r'[,;]|\band\b'))
        .map(_normalise)
        .where((String part) => part.isNotEmpty && !_onlyFiller.hasMatch(part))
        .toList();
    final List<String> said = parts
        .where((String part) => !_dayAlone.hasMatch(part))
        .toList();
    // "Tomorrow:", "Okay, for Saturday." — the day, which the extractor
    // reads as the day of what follows. Set aside only beside a preamble.
    if (said.length != parts.length && !said.any(_isPreambleText)) {
      return false;
    }
    return said.every(
      (String part) => _smallTalk.hasMatch(part) || _isPreambleText(part),
    );
  }

  /// Whether [clause] asks rather than says what to do: "did I pay the phone
  /// bill?", "is the printer still broken?", "what time does the party
  /// start?" — or wonders aloud: "I wonder if he fixed the heating".
  ///
  /// ⚠️ Only a question that cannot be an order: "Do the laundry?" and "Have
  /// lunch with Sherzod?" are tasks whisper ended with a question mark, and
  /// "Can you remind me to…?", "How about…?" ask for one.
  static bool isQuestion(String clause) {
    final String text = _normalise(clause);
    if (_wondering.hasMatch(text)) return true;
    return clause.trimRight().endsWith('?') && _asking.hasMatch(text);
  }

  static final RegExp _asking = RegExp(
    '^$_filler'
    r"(?:(?:is|are|was|were|am|isn't|aren't|wasn't|weren't|didn't|doesn't)\b"
    r'|(?:do|does|did|have|has|had)'
    r' (?:i|we|you|he|she|they|it|the|my|our|his|her|their|this|that)\b'
    r'|(?:what|where|why|who|whose|which|how)\b(?! about\b)'
    // ⚠️ Not "When I get home, call mom?": a condition, then the task.
    r'|when (?:is|are|was|were|do|does|did|will|should|can)\b)',
  );

  static final RegExp _wondering = RegExp(
    '^$_filler'
    r"(?:i|we)(?: wonder| wondered| was wondering| am wondering|'m wondering"
    r"| are wondering|'re wondering) (?:if|whether|why|what|when|where|who"
    r'|how)\b',
  );

  /// "I have some tasks for today", "Tomorrow I have three things", "Here is
  /// my list" — an announcement that tasks follow.
  ///
  /// Kept apart from [isNonTask] because a preamble's date still matters: in
  /// "Tomorrow I have three things. First, go to the bank…" every task that
  /// follows belongs to tomorrow.
  static bool isPreamble(String clause) =>
      clause.split(RegExp(r'[,;]')).map(_normalise).any(_isPreambleText);

  static bool _isPreambleText(String text) => _preamble.hasMatch(text);

  /// "we are jumping", "I am tired", "it is raining" — narration with a
  /// subject and a form of "to be", which says how things are rather than what
  /// to do.
  static bool isNarration(String fragment) {
    final String text = _normalise(fragment);
    if (isState(fragment)) return true;
    final RegExpMatch? match = _narrationIn(text);
    if (match == null) return false;
    // ⚠️ "I'm going to call Anna", "I'm meeting Sardor for lunch", "we're
    // picking up Max" are plans, which is what a to-do list is made of. A
    // progressive is narration only when its verb is not one a task starts
    // with ("we are jumping"), the speaker says it is happening now ("I'm
    // walking to the office right now"), or it is somebody else's plan: "he
    // is moving to Korea", "my husband is coming home early".
    final String? ing = match[2];
    if (ing == null) return true;
    if (_happeningNow.hasMatch(text)) return true;
    if (!_speaker.hasMatch(match[1] ?? '')) return true;
    return ClauseLexicon.progressiveVerb(ing) == null;
  }

  /// Whether [clause] is only about someone else — "my sister is coming from
  /// Moscow on the 28th", "he is moving to Korea" — with nothing in it for
  /// the speaker to do. Unlike other narration it may carry a date, which is
  /// the day the speaker goes on to talk about.
  static bool isAboutSomeoneElse(String clause) {
    final String text = _normalise(clause);
    final RegExpMatch? match = _narrationIn(text);
    if (match == null || match[1] == null || _speaker.hasMatch(match[1]!)) {
      return false;
    }
    final int after = text.indexOf(match[1]!) + match[1]!.length;
    return !RegExp(r"\b(?:i|we|i'm|we're|i'll|we'll|me|us)\b")
        .hasMatch(text.substring(after));
  }

  static final RegExp _speaker = RegExp(r'^(?:i|we)\b');

  /// Whether [clause] only says how the speaker stands — "I'm free
  /// tomorrow", "I'm set for Friday", "I'm close to the mall", "we are busy
  /// on Saturday" — which is never a task, though its day may be the day of
  /// the one after it.
  static bool isSpeakerState(String clause) {
    final String text = _normalise(clause);
    if (!isNarration(clause)) return false;
    final RegExpMatch? match = _narrationIn(text);
    return match != null &&
        match[1] != null &&
        _speaker.hasMatch(match[1]!) &&
        match[2] == null;
  }

  /// "Tomorrow is Friday", "today's Monday" — which day it is, said aloud.
  /// Never a task; its day may be the day of the one after it: "tomorrow
  /// will be Monday, so pay the rent".
  static bool namesTheDay(String clause) =>
      _namesTheDay.hasMatch(_normalise(clause));

  static final RegExp _namesTheDay = RegExp(
    '^$_filler'
    r"(?:today|tomorrow|tonight)(?: is|'s| will be) (?:a )?(?:monday|tuesday"
    r'|wednesday|thursday|friday|saturday|sunday)'
    r'(?: (?:so|and|then|already))?$',
  );

  /// A state that is never a task, whatever else it names: how today is or
  /// was ("today is my father's birthday"), or where the speaker is right now
  /// ("I'm at the gym now"). The gym and the birthday are not errands.
  static bool isAside(String clause) {
    final String text = _normalise(clause);
    return _aside.hasMatch(text) && !_dayOfSomethingToDo(text);
  }

  /// "Today is the last day to pay the parking fine", "today is the deadline
  /// to submit the essay" — the day described is the day of a task, which
  /// the infinitive names.
  ///
  /// ⚠️ Without this, "today is…" threw the whole clause away, the errand in
  /// it included: a note that was nothing but a deadline came back empty.
  static bool _dayOfSomethingToDo(String text) {
    final Match? day = _todayIs.matchAsPrefix(text);
    if (day == null) return false;
    return _infinitive
        .allMatches(text, day.end)
        .any((RegExpMatch m) => ClauseLexicon.isImperativeVerb(m[1]!));
  }

  static final RegExp _todayIs = RegExp(
    '$_filler'
    r"(?:today|yesterday) (?:is|was|'s|has been)\b",
  );

  static final RegExp _infinitive = RegExp(r'\bto ([a-z]+)\b');

  static final RegExp _aside = RegExp(
    '^$_filler'
    r"(?:(?:today|yesterday) (?:is|was|'s|has been)\b"
    r"|(?:i'm|i am|we're|we are) (?:on|in|at)\b.*\b(?:now|right now"
    r'|at the moment)\b)',
  );

  /// "Sardor called, he said the meeting is moved", "my brother said this
  /// app is good" — what somebody else said or did, even with a day in it.
  ///
  /// ⚠️ Not "she asked me to…", "he told me to…", "Anna said to…": that is
  /// an errand handed over, and the task is what follows the "to".
  ///
  /// ⚠️ Nor "install app called Payme", "read book called Atomic Habits": a
  /// report opens with who spoke, and a clause that opens with a verb a task
  /// starts with is the task — its "called" names the object. People learning
  /// English drop the article, so "app called" alone cannot tell them apart.
  static bool isReport(String clause) {
    final RegExpMatch? match = _report.firstMatch(_normalise(clause));
    if (match == null) return false;
    final String head = match[1]!;
    return !ClauseLexicon.isImperativeVerb(head) &&
        !ClauseLexicon.isLeadingOnlyVerb(head);
  }

  static final RegExp _report = RegExp(
    '^$_filler'
    r"(?:(?:my|our|his|her) )?([a-z']+)(?: [a-z']+)? "
    r'(?:said|says|told (?:me|us)|wrote|called|texted|messaged)\b'
    r'(?! (?:me |us )?to\b)',
  );

  static final RegExp _happeningNow = RegExp(
    r'\b(?:right now|at the moment|currently|as we speak)\b',
  );

  /// Narration that is never a task even with a when in it: "the weather is
  /// really nice today", "I'm on the bus right now", "the meeting went well".
  /// Unlike "I'm meeting Sardor at 5", nothing here can be scheduled.
  static bool isState(String fragment) {
    final String text = _normalise(fragment);
    return _state.hasMatch(text) && !_dayOfSomethingToDo(text);
  }

  static final RegExp _state = RegExp(
    // ⚠️ The same filler the splitter and the title cleaner skip: without
    // "listen", "Uh, listen, the internet is not working again" became a task.
    // "I guess" and "I think" too: "Ah yes" comes back from whisper as "I
    // guess", and "I guess the internet at home is not working" was a card.
    r'^(?:and |but |so |okay |ok |oh |ah |ooh |yes '
    r'|yeah |well |anyway |listen |actually |honestly |basically '
    r'|i guess |i think |i mean |you know '
    '|(?:${ClauseLexicon.hesitations}) )*(?:'
    // where the speaker is
    r"(?:i'm|i am|we're|we are) (?:on|in|at|stuck|still|already|almost)\b"
    // weather and how things are
    r"|(?:the|it|it's|this) ?(?:weather|sun|rain|day|traffic|bus|metro)?"
    r" ?(?:is|was|'s)? (?:(?:really|very|so|pretty|quite) )?"
    r'(?:nice|good|bad|great|cold|hot|warm|sunny|crowded|raining|snowing'
    r'|busy|terrible|awful|lovely|beautiful|out)\b'
    // how something went
    r'|(?:the|my|our) (?:[a-z]+ )?(?:[a-z]+ )?(?:went|was|were|has been)\b'
    // how something is: "my phone is almost dead", "the internet at home is
    // not working since yesterday" — and "the Wi-Fi at home is not working",
    // whose hyphen kept it a card.
    r"|(?:the|my|our|his|her|this|that) (?:[a-z'-]+ ){1,3}"
    r"(?:is|are|isn't|aren't|was|wasn't) (?:(?:not|still|almost|already"
    r'|completely|totally|very|so|again|really) )*(?:working|broken|dead'
    r'|finished|empty|full|low|crowded|closed|late|terrible|awful|angry|sick'
    r'|tired|busy)\b'
    // how today is or was: "today was crazy at work", "today is my father's
    // birthday" — the day being described, not something to do in it
    r"|(?:today|yesterday) (?:is|was|'s|has been)\b"
    r')',
  );

  static String _normalise(String text) => text
      .toLowerCase()
      .replaceAll('\u2019', "'")
      .replaceAll(RegExp(r'[^a-z0-9\s\x27-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const String _filler =
      '(?:(?:${ClauseLexicon.hesitations}'
      r'|okay|ok|so|well|alright|all right|oh|yeah|yes'
      r'|hi|hey|hello|ah|ooh|wow|anyway|and|but)\s+)*';

  /// A comma-separated piece that says nothing. "like" counts only here, as a
  /// whole piece: "I have to, like, buy milk". "So, I have three tasks for
  /// tomorrow" — the "so" said nothing, and it kept the preamble a card.
  static final RegExp _onlyFiller = RegExp(
    '^(?:$_fillerWord)(?:\\s+(?:$_fillerWord))*\$',
  );

  static const String _fillerWord =
      '${ClauseLexicon.hesitations}|ah|ooh|like|so|well|oh|and|but|then|now';

  /// A piece that is only the day, or the day and a dangling "is": "Tomorrow,
  /// I have two tasks", "Tomorrow is, I have some tasks" — the speaker
  /// starting the sentence twice. The day still frames the list.
  static final RegExp _dayAlone = RegExp(
    '^(?:for |on )?$_day(?: is| was| will be|\x27s)?\$',
  );

  /// The day a list is for: "tomorrow", "this Friday", "Monday morning",
  /// "October 5th".
  static const String _day =
      r'(?:today|tomorrow|tonight|this (?:morning|afternoon|evening|week'
      r'|weekend)|next (?:week|weekend)'
      r'|(?:this |next )?(?:monday|tuesday|wednesday|thursday|friday|saturday'
      r'|sunday)|(?:the \d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th))'
      '(?: of $_month)?|$_month (?:the )?\\d{1,2}(?:st|nd|rd|th)?)'
      r'(?: (?:morning|afternoon|evening|night))?';

  static const String _month =
      r'(?:january|february|march|april|may|june|july|august|september'
      r'|october|november|december)';

  static final RegExp _smallTalk = RegExp(
    '^$_filler'
    // "Hi Anna", "thanks Anna" — the name is who is spoken to.
    r'(?:(?:hi|hey|hello)(?: [a-z]+)?|good (?:morning|afternoon|evening|night)'
    r"|how are you(?: doing)?(?: today)?|how's it going|what's up"
    r'|thank you(?: very much| so much)?(?: for .*| [a-z]+)?'
    r'|thanks(?: a lot)?(?: for .*| [a-z]+)?'
    // "Perfect, send it to Anna", "Done. Send it to the client." — a
    // reaction to what came before. ⚠️ Kept, it was a card of its own, or
    // the thing an "it" after it stood for: "Send perfect to Anna".
    r'|(?:very |really |so )?(?:perfect|good|fine|nice|excellent|awesome'
    r'|wonderful|fantastic|brilliant|lovely|super|amazing|done|exactly'
    r'|correct|true)|of course|no problem|got it|understood|good job|well done'
    r"|let's go|let us go|bye|goodbye|good bye|see you(?: later| soon)?"
    r'|ok|okay|yes|no|yeah|yep|nope|sure|alright|all right|right|great|cool'
    r"|that's (?:it|all)(?: for now| for today)?|that is (?:it|all)(?: for now)?"
    r'|nothing(?: else)?|never mind|testing(?: testing)?(?: one two three)?'
    r"|(?:i'm|i am) (?:just )?testing(?: (?:this|it|the (?:app|mic|microphone))"
    r'| (?:if|whether) .*)?|test'
    r"|it's (?:very )?(?:nice|good|great|cool)|this is (?:very )?(?:nice|good|great|cool)"
    r"|let me (?:think|see)|i think that's (?:it|all)|that's everything"
    r'|(?:and )?one more thing|(?:may|can|could) i add (?:one|another) (?:more|thing|task)(?: thing)?'
    r'|(?:um |uh )?where was i|what else|one|two|three|four|five|testing|have a (?:nice|good|great|lovely) (?:day|evening|night|weekend|one)|is this (?:thing )?working|can you hear me|anyway'
    // "is this thing on?", "is it recording?"
    r'|is (?:this|it) (?:thing )?(?:on|recording|working)'
    // "Oh I almost forgot", "I forgot what I wanted to say" — and not "I
    // forgot to call Anna", which is a task.
    r'|(?:i )?(?:almost |nearly |totally )?forgot'
    r'(?: what i (?:wanted|was going) to (?:say|tell you|ask))?'
    r'|man|oh man|my god|oh my god|what a (?:day|week|morning|night|mess)'
    r'|wait|hold on|sorry|excuse me|no nothing|nothing sorry'
    // "Hmm, what was it... ah yes, the washing machine" — thinking aloud.
    r'|what was (?:it|that|i (?:saying|going to say))'
    r"|(?:i'm|i am) (?:just )?trying (?:it|this|the app)(?: out)?"
    r')(?:\s+(?:please|then|now|thanks|thank you|sorry|wow))?$',
  );

  static final RegExp _preamble = RegExp(
    '^$_filler'
    // "Tomorrow I have…", "on Friday there are…", "for tomorrow I have…"
    '(?:(?:for |on )?$_day\\s+)?'
    r"(?:(?:(?:i|we) (?:have|have got|'ve got|got|need to do|must do|want to do"
    r'|should do)'
    r'|there (?:are|is)|here (?:are|is)|here s|these are|this is)\s+)?'
    // ⚠️ Any number of them: whisper wrote "I have one some tasks" for a
    // speaker who changed their mind mid-word. One word each — "a few",
    // "a lot of" are two and three — so that a phrase can be read only one
    // way: with "a few" as well as "a" and "few", whisper looping "a few a
    // few a few…" took 16 seconds to fail.
    r'(?:(?:some|a|an|few|couple|of|lots|lot|many|several|my|the|our|\d+'
    r'|one|single|two|three|four|five|six|seven|eight|nine|ten)\s+)*'
    // "the last thing, call Anna", "one last thing" — what comes next, not
    // a thing the task is about.
    r'(?:small |little |important |quick |more |other |last |final |next )?'
    // "work stuff", "house things", "school tasks"
    r'(?:(?:work|home|house|household|school|university|family|office'
    r'|personal|business) )?'
    r'(?:tasks?|things?|items?|to[ -]?dos?|errands?|stuff|jobs?'
    r'|(?:to[ -]?do |task |shopping )?list|plans?|reminders?)'
    // "…for tomorrow", "…for Friday", "…on the 5th", "…to do today"
    '(?:\\s+(?:to do|for now|for the (?:day|week|weekend)'
    '|(?:for |on )?$_day))*'
    // "My to-do list for tomorrow is: call the bank…"
    r'(?:\s+(?:is|are|include))?$',
  );

  /// [_narration] in [text] — unless its subject is two things joined by
  /// "and" and the first is a verb: "call Aziz and Madina are…" is a task
  /// gone wrong, not two people.
  static RegExpMatch? _narrationIn(String text) {
    final RegExpMatch? match = _narration.firstMatch(text);
    final String? subject = match?[1];
    if (subject == null || !subject.contains(' and ')) return match;
    final String first = subject.split(' ').first;
    return ClauseLexicon.isImperativeVerb(first) ||
            ClauseLexicon.isLeadingOnlyVerb(first)
        ? null
        : match;
  }

  static final RegExp _narration = RegExp(
    '^$_filler(?:'
    r'(i|we|he|she|they|it|you|everyone|everybody'
    // Two who are coming: "the kids and their friends are coming", "my
    // parents and my sister are coming", "Aziz and Madina are coming".
    // ⚠️ Only with "are" or "were": one of them was a card of its own, "My
    // parents", or the pair was — "Aziz and Madina are coming".
    r"|(?:(?:my|our|his|her|their|the) )?[a-z']+(?: [a-z']+)?"
    r" and (?:(?:my|our|his|her|their|the) )?[a-z']+"
    r"(?= are\b| were\b|'re\b)"
    // "my sister Dilnoza is coming", "the plumber is coming tomorrow"
    // "my sister Dilnoza", and a name whisper heard as two words: "my
    // assistant or nozo is coming", "my sister, Don Noser, is coming".
    r"|(?:my|our|his|her|the) [a-z']+(?: [a-z']+){0,2})"
    r"(?: am| are| is| was| were|'m|'re|'s)"
    r'(?: (?:so|very|really|just|still|all|finally))?'
    r' (?:([a-z]+ing)|tired|happy|sad|busy|fine|ok|okay|good|great|ready|late'
    // "I'm free tomorrow", "I'm set for Friday", "I'm close to the mall" —
    // not "I'm set to call Anna", which is the task.
    r'|(?:free|set|available)(?! to\b)|close|near|done'
    r'|here|there|home|back)\b'
    // "the sun is out", "it's raining", "the weather is nice"
    r"|(?:the|this|that|it|there|my) (?:[a-z]+ )?(?:is|are|was|were|'s)"
    r' (?:out|nice|good|bad|great|cold|hot|warm|sunny|raining|snowing|here'
    r'|there|ready|done|fine|late|early)\b)'
    r'.*$',
  );
}
