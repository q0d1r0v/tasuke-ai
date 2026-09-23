import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';

import 'clause_splitter.dart';
import 'extracted_task.dart';
import 'extraction_defaults.dart';
import 'non_task.dart';
import 'task_extractor.dart';
import 'time_grammar.dart';
import 'title_cleaner.dart';
import 'transcript_normaliser.dart';
import 'when_parser.dart';

/// Turns one transcript into tasks with deterministic rules: split, parse the
/// when, clean the title.
///
/// It is the app's only extractor — the pipeline's primary and its fallback
/// both — so there is nothing to download or warm up, and the labelled corpora
/// in `test/fixtures/nl` measure exactly what the user gets.
final class RuleBasedTaskExtractor implements TaskExtractor {
  const RuleBasedTaskExtractor({
    this.normaliser = const TranscriptNormaliser(),
    this.splitter = const ClauseSplitter(),
    this.parser = const WhenParser(),
    this.cleaner = const TitleCleaner(),
  });

  /// Undoes how whisper writes a note down before any rule reads it.
  final TranscriptNormaliser normaliser;
  final ClauseSplitter splitter;
  final WhenParser parser;
  final TitleCleaner cleaner;

  /// Always. There is nothing to load — that is the entire point of it.
  @override
  Future<bool> isReady() async => true;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async {
    final List<ExtractedTask> tasks = <ExtractedTask>[];

    // The date the speaker has put the rest of the note under, if any:
    // "Tomorrow I have three things. First…", "For Saturday:".
    LocalDate? headerDate;
    // A heading's time belongs to the ONE task after it: "Tomorrow at 9. Call
    // Anna." — and the date that time resolved to when no day was said.
    LocalTimeOfDay? headerTime;
    LocalDate? headerTimeDate;
    bool headerReminder = false;
    // "Tonight I have one thing. Call Anna at 9." — a 9 that means 21:00.
    bool eveningContext = false;
    // …and under a night, not an evening, "at 2" is 02:00 after midnight.
    bool nightContext = false;
    // The day being talked about, for a later clause that gives only a time.
    LocalDate? spokenDate;
    // The last afternoon/evening time said, and its day: in "buy milk at 5
    // p.m. Call Anna at 7" the 7 is 19:00 today, not 07:00 tomorrow.
    LocalTimeOfDay? lastPm;
    LocalDate? lastPmDate;
    // The day a clause opened with, for the clauses after it in the same
    // sentence that say no when at all, however they are joined: "Tomorrow
    // buy a charger, call Umid" is two things for tomorrow. A day said last
    // goes only as far as [firstDay] takes it.
    LocalDate? runDate;
    // Where the current sentence's tasks start, for "…, both on Friday".
    int sentenceStart = 0;
    // "The plumber is coming tomorrow at 10, so I have to be at home": the
    // time of somebody else's plan, for the one task that answers it.
    LocalTimeOfDay? runTime;
    // The clause the last task came from: "the rent is due on the 1st"
    // before "remind me two days before".
    String lastTaskClause = '';
    // "Remind me at 7 pm to take my pills and to lock the garage": a when
    // said before the first "to" is the when of every "to" after it in the
    // sentence.
    ({LocalDate? date, LocalTimeOfDay? time})? remindWhen;
    // The day of the sentence's first task, for the tasks joined to it with
    // "and" or "then" that say no when at all: "Buy a cake for Nodira on
    // Saturday and order balloons" is two things for Saturday, "Call mom
    // tonight and pay the bill" two for today — and so is whisper's "Call
    // the plumber tomorrow at 2pm. And text Bekzod the address." Only the
    // day: the balloons are not at the cake's hour. ⚠️ Only the first
    // task's: in "…to check the hall tomorrow and to buy candles" each task
    // before the candles had a when of its own, and the candles none.
    LocalDate? firstDay;

    final List<SplitClause> said = splitter.split(
      normaliser.normalise(transcript, now: now),
    );
    final List<String> clauses = <String>[
      for (final SplitClause c in said) c.text,
    ];
    for (int index = 0; index < clauses.length; index++) {
      final String clause = clauses[index];
      final bool isLast = index == clauses.length - 1;
      // "and", "then", "after that" — and whisper's ". And", ". Then": the
      // next thing, on the same occasion.
      // ⚠️ Not an afterthought: "…and, oh, pay the bill", "And by the way,
      // get the tyres changed" start something new, like "Oh, and…".
      final bool follows =
          _sequence.contains(said[index].joint) &&
          !_afterthought.hasMatch(foldTemporalCase(clause));
      if (tasks.length >= ExtractionDefaults.maxTasksPerCapture) break;
      if (index > 0 && _sentenceEnd.hasMatch(clauses[index - 1])) {
        runDate = null;
        runTime = null;
        remindWhen = null;
        sentenceStart = tasks.length;
      }
      // ⚠️ A list ("…on Friday, order balloons, and…") or an "Oh, and…"
      // afterthought does not say whose day it is.
      if (!follows) firstDay = null;
      final ParsedWhen when = parser.parse(clause, now: now);
      // "Fixed the sink yesterday", "Sent the contract to the lawyer this
      // morning" said in the afternoon: done, on a day already gone. A past
      // tense with no when, or a when still ahead, stays a card with the
      // words as said — whisper writes "call the bank" as "called the bank".
      if (_doneAlready(clause, when, now)) continue;
      // "Did I pay the phone bill?", "I wonder if he fixed the heating" —
      // asked, not said to do. ⚠️ Kept, each was a card, and took the day of
      // the task before it.
      if (when.isEmpty && NonTask.isQuestion(clause)) continue;
      final bool remind = _remindWords.hasMatch(clause);
      // "at some point", "whenever I have time", "no rush", "eventually": no
      // day, said out loud — so none is carried over from the task before.
      final bool vague = ClauseLexicon.vagueWhen.hasMatch(
        foldTemporalCase(clause),
      );
      // "once it's fixed", "when the salary comes", "after payday": done
      // when something else happens, on a day nobody said.
      final bool awaits = _awaitsEvent.hasMatch(foldTemporalCase(clause));

      // "The weather is nice", "I'm on the bus", "the meeting went well" —
      // context, not a task. Kept only when it names both something to do or
      // attend AND a when: "the meeting was moved to Thursday at 3".
      if (NonTask.isState(clause) &&
          (when.isEmpty || !_hasAction(clause) || NonTask.isAside(clause))) {
        continue;
      }
      // "Sardor called, he said the meeting is moved to Friday" — news, even
      // with a day in it. What to do about it is said next, or not at all.
      if (NonTask.isReport(clause)) continue;
      if (NonTask.isAboutSomeoneElse(clause) && !when.isEmpty) {
        // After a task it explains it: "cook dinner before 6, my husband is
        // coming home early today". Before one, it is the day of what the
        // speaker does about it: "my sister is coming on the 28th, I need to
        // pick her up at 11 at night". Alone, it is an event of its own.
        final bool explains = tasks.length > sentenceStart;
        // ⚠️ An appointment — a plan with a clock time — frames only a task
        // with no day of its own. In "the electrician is coming tomorrow at
        // 10, so today buy the cable" the cable is today's and the
        // electrician is tomorrow at 10, somebody to be home for: framed, he
        // was lost and his 10:00 went to the next task. A plan with only a
        // day ("my sister is getting married on the 17th, so next week buy a
        // gift") is the reason for what follows, like a "because".
        final bool frames =
            !isLast &&
            !_sentenceEnd.hasMatch(clause) &&
            !(when.time != null &&
                _hasDayOfItsOwn(clauses[index + 1], when, now));
        if (explains) {
          // "Tomorrow go to the bank, the manager is waiting at 11 a.m." — a
          // time with no day is when the task just said happens.
          final ExtractedTask? timed = _timed(tasks.last, when, now);
          if (timed != null) tasks.last = timed;
          continue;
        }
        if (frames) {
          if (when.dateSpoken) {
            spokenDate = when.date;
            runDate = when.date;
          }
          runTime = when.time;
          continue;
        }
      } else if (NonTask.isAboutSomeoneElse(clause)) {
        // "…, he is moving to Korea."
        continue;
      }
      if (NonTask.isNarration(clause) && when.isEmpty) continue;
      // "I'm free tomorrow, clean the garage", "I'm set for Friday, so today
      // buy the gift": how the speaker stands on a day is no task — the day
      // is the one of the task after it, unless that names its own.
      if (when.dateSpoken && NonTask.isSpeakerState(clause)) {
        if (when.confidence == Confidence.high &&
            !isLast &&
            !_sentenceEnd.hasMatch(clause) &&
            !_hasDayOfItsOwn(clauses[index + 1], when, now)) {
          spokenDate = when.date;
          runDate = when.date;
        }
        continue;
      }
      if (NonTask.isNonTask(clause)) {
        // "I have some tasks for today", "Hello", "Thank you." — not a card.
        // A preamble's day still frames what follows it.
        if (NonTask.isPreamble(clause) && when.dateSpoken) {
          headerDate = when.date;
          eveningContext = _evening.hasMatch(clause);
          nightContext = _night.hasMatch(clause);
        }
        continue;
      }

      String title = cleaner.clean(
        clause,
        matchStart: when.matchStart,
        matchEnd: when.matchEnd,
        spans: when.spans,
      );

      // "…I'm flying to Seoul, the flight is at 6 in the morning": the time of
      // the task just said, not a task called "The flight".
      if (tasks.length > sentenceStart &&
          tasks.last.date != null &&
          _elaborates(foldTemporalCase(clause), tasks.last.title)) {
        final ExtractedTask? timed = _timed(tasks.last, when, now);
        if (timed != null) {
          tasks.last = timed;
          continue;
        }
      }
      // "…submit the report on Wednesday, and remind me the day before at
      // 9" — when to be told about the task before, counted back from its
      // day. ⚠️ Read as a task, it was a card titled "The day" on the
      // report's own day, and the report had no reminder at all. With no
      // task before it, it is about nothing: not a card called "The day".
      final RegExpMatch? earlier = remind
          ? _remindEarlier.firstMatch(foldTemporalCase(clause))
          : null;
      final String? beforehand = earlier == null
          ? null
          : cleaner.clean(
              clause,
              matchStart: 0,
              matchEnd: 0,
              spans: <MatchSpan>[
                ...when.spans,
                MatchSpan(earlier.start, earlier.end),
              ],
            );
      // With no day to count back from, "the day before" is no title either.
      if (beforehand != null && beforehand.isNotEmpty) title = beforehand;
      // "My flight is on Friday, remind me the day before to pack" — a task
      // of its own, on the day counted back from the one before. ⚠️ Read as
      // a when-less task, it was a card titled "The day before to pack".
      final LocalDate? before = tasks.isEmpty ? null : tasks.last.date;
      if (earlier != null &&
          beforehand != null &&
          beforehand.isNotEmpty &&
          before != null &&
          !when.dateSpoken) {
        final LocalDate day = before.addDays(-_daysEarlier(earlier));
        tasks.add(
          ExtractedTask(
            title: beforehand,
            date: day.isBefore(now.date) ? now.date : day,
            time: when.time,
            hasReminder: true,
            whenText: clause.substring(earlier.start, earlier.end),
          ),
        );
        lastTaskClause = clause;
        continue;
      }
      if (earlier != null && beforehand != null && beforehand.isEmpty) {
        if (tasks.isEmpty) continue;
        tasks.add(
          _remindedEarlier(
            tasks.removeLast(),
            lastTaskClause,
            when,
            _daysEarlier(earlier),
            now,
          ),
        );
        continue;
      }
      if (title.isEmpty && tasks.isNotEmpty && remind) {
        // "…call Anna. Remind me at 5." — about the task before, not a task
        // of its own. Its when is the reminder the user asked for.
        tasks.add(_withReminder(tasks.removeLast(), when));
        continue;
      }
      if (title.isEmpty && !when.isEmpty && !isLast) {
        // "Tomorrow at 9.", "For Saturday:", "Remind me at 5." — a heading for
        // what follows. Only with something after it: a note that is nothing
        // but "tomorrow at 3 PM" is still a task to rename.
        if (when.dateSpoken) headerDate = when.date;
        headerTime = when.time;
        headerTimeDate = when.date;
        headerReminder = remind;
        eveningContext = _evening.hasMatch(clause);
        nightContext = _night.hasMatch(clause);
        continue;
      }
      if (title.isEmpty) {
        // "Tomorrow at three" with no verb at all. Keeping the words the user
        // said beats dropping the capture on the floor — the Confirm screen is
        // where they fix it.
        title = cleaner.clean(clause, matchStart: 0, matchEnd: 0);
      }
      // "Test" said alone is a mic check; "Test tomorrow at 9" is a task.
      if (title.isEmpty || (NonTask.isNonTask(title) && when.isEmpty)) {
        continue;
      }

      LocalDate? date = when.date;
      LocalTimeOfDay? time = when.time;
      bool reminder = _wantsReminder(clause, when);
      if (when.dateSpoken) {
        // ⚠️ Not a deadline, and not a vague "next week": "submit the report
        // by Friday. Call Anna at 3." does not mean Friday at 3.
        spokenDate =
            _isDeadline(clause, when) || when.confidence != Confidence.high
            ? null
            : when.date;
      } else if (time != null &&
          (spokenDate ?? headerDate ?? lastPmDate) != null) {
        // "…then at twelve lunch with Dilnoza": a time with no day of its own
        // belongs to the day already being talked about — unless that would
        // put it in the past.
        final LocalDate context = (spokenDate ?? headerDate ?? lastPmDate)!;
        final bool continuesAfternoon =
            lastPm != null &&
            time.minuteOfDay < 12 * 60 &&
            time.minuteOfDay + (12 * 60) > lastPm.minuteOfDay;
        // ⚠️ Under "Tonight I have one thing.", "at midnight" is not noon and
        // "at 2" is 02:00 after midnight, not 14:00: the small hours
        // WhenParser gives "tonight at 2". The 2 only on the heading's night.
        final LocalTimeOfDay? small = eveningContext && !_saidMeridiem(clause)
            ? WhenParser.smallHours(
                _whenTextOf(clause, when) ?? '',
                time,
                night: nightContext && context == headerDate,
              )
            : null;
        final LocalTimeOfDay said =
            small ??
            ((eveningContext || continuesAfternoon) && !_saidMeridiem(clause)
                ? _toEvening(time)
                : time);
        // Said at 00:40, "tonight" is the night already under way.
        final bool stillTonight =
            small != null &&
            context == now.date &&
            small.minuteOfDay > now.time.minuteOfDay;
        final LocalDate day = small == null || stillTonight
            ? context
            : context.addDays(1);
        if (!LocalDateTime(day, said).isBefore(now)) {
          date = day;
          time = said;
        }
      } else if (when.isEmpty) {
        final LocalTimeOfDay? pending = headerTime;
        final ({LocalDate? date, LocalTimeOfDay? time})? shared = remindWhen;
        if (shared != null &&
            _toInfinitive.hasMatch(foldTemporalCase(clause))) {
          // ⚠️ Left without it, "Lock the garage" had no day and no time,
          // and no reminder either, though one was asked for.
          date = shared.date;
          time = shared.time;
          reminder = true;
        } else if (pending != null) {
          time = pending;
          date = headerDate ?? headerTimeDate;
          reminder = true;
          headerTime = null;
        } else if (vague) {
          date = null;
        } else if (awaits) {
          // ⚠️ Only a heading still says it: under "Tomorrow I have three
          // things", "when Aziz comes, give him the keys" is tomorrow's.
          date = runDate == null ? headerDate : null;
        } else if (firstDay != null &&
            follows &&
            (said[index].joint != SplitClause.and || !_newStatement(clause))) {
          date = firstDay;
        } else if (runDate != null || headerDate != null) {
          date = runDate ?? headerDate;
          time = runTime;
          runTime = null;
        }
      }
      // "My sister is coming tomorrow at 5, tomorrow pick her up": the task
      // that answers somebody else's plan on the plan's own day is at its
      // time, whether or not it says the day again.
      if (runTime != null && time == null && date != null && date == runDate) {
        time = runTime;
        reminder = true;
      }
      if (headerReminder && headerTime == null) {
        reminder = true;
        headerReminder = false;
      }
      // An undated sentence of its own ends the run of a spoken day: in
      // "Call mom on Friday. Buy milk. Pick up the kids at 4." the kids are
      // today, not Friday.
      if (date == null && time == null && _sentenceEnd.hasMatch(clause)) {
        spokenDate = null;
      }

      if (tasks.any(
        (ExtractedTask t) =>
            t.title.toLowerCase() == title.toLowerCase() &&
            t.date == date &&
            t.time == time,
      )) {
        // whisper repeats itself on a long pause: "Call the dentist tomorrow.
        // Call the dentist tomorrow." is one task said twice.
        continue;
      }

      if (time != null) {
        final bool pm = time.minuteOfDay >= 12 * 60;
        lastPm = pm ? time : null;
        lastPmDate = pm ? date : null;
      }
      // A task with a when of its own ends the first one's day; the first
      // task of a sentence starts it. ⚠️ Not a deadline ("by Friday"), not
      // "in two hours", not a vague "next week": not a day for what follows.
      if (!when.isEmpty || vague) firstDay = null;
      if (tasks.length == sentenceStart &&
          when.dateSpoken &&
          when.confidence == Confidence.high &&
          !_isDeadline(clause, when) &&
          !_relative.hasMatch(_whenTextOf(clause, when) ?? '')) {
        firstDay = date;
      }
      if (vague) {
        runDate = null;
      } else if (when.dateSpoken) {
        // ⚠️ Not a deadline ("by Friday finish X, and…"), not a vague "next
        // week", and not "in two hours": a moment for one thing, not a day
        // for everything after it.
        runDate =
            _isFronted(clause, when) &&
                when.confidence == Confidence.high &&
                !_isDeadline(clause, when) &&
                !_relative.hasMatch(_whenTextOf(clause, when) ?? '')
            ? when.date
            : null;
      }
      // "Call the vet and book the groomer, both on Friday": the day is for
      // every task of the sentence that has none of its own.
      if (when.dateSpoken && _distributive.hasMatch(foldTemporalCase(clause))) {
        for (int i = sentenceStart; i < tasks.length; i++) {
          if (tasks[i].date == null && tasks[i].time == null) {
            tasks[i] = tasks[i].copyWith(date: date, time: time);
          }
        }
      }

      tasks.add(
        ExtractedTask(
          title: title,
          date: date,
          time: time,
          hasReminder: reminder,
          confidence: when.confidence,
          whenText: _whenTextOf(clause, when),
        ),
      );
      lastTaskClause = clause;
      if (remind) {
        remindWhen = _saidBeforeTheTo(clause, when)
            ? (date: date, time: time)
            : null;
      }
      // ⚠️ Somebody else's time is for the ONE task that answers it, whether
      // or not that task took it: left over, it went to the task after, in
      // "…, so today buy the cable and call Anna" a call five hours ago.
      runTime = null;
    }
    return tasks;
  }

  /// Whether [clause] opens with a past tense ("fixed", "sent", "paid",
  /// "went") and its when is already over.
  ///
  /// ⚠️ Not "got to": "Got to call the bank" is a "have to". And every part
  /// of it must be done: in "Did the laundry this morning, fold it tonight",
  /// glued into one clause, the folding is still to do — dropped whole, it
  /// was lost.
  static bool _doneAlready(String clause, ParsedWhen when, LocalDateTime now) {
    if (!when.isOverAt(now)) return false;
    final List<String> parts = clause.split(',');
    for (int i = 0; i < parts.length; i++) {
      final String folded = foldTemporalCase(parts[i]);
      final int start = ClauseSplitter.taskStartIn(folded);
      if (i > 0 && start >= folded.trimRight().length) continue;
      final String verb = wordAfter(folded, start);
      if (!ClauseLexicon.isPastTense(verb)) return false;
      final int end = folded.indexOf(verb, start) + verb.length;
      if (verb == 'got' && wordAfter(folded, end) == 'to') return false;
    }
    return true;
  }

  /// Whether [clause] starts a statement of its own — "I also need to renew
  /// my passport", "we should repaint the kitchen" — rather than go on with
  /// the task before it.
  ///
  /// ⚠️ After "and", a clause with its own "I" says a new thing, and the day
  /// said inside the task before is not its day: in "Call Anna tomorrow and
  /// I also need to renew my passport" the passport has none. "Then", "after
  /// that" still order it after that task, on its day — the caller asks
  /// only after a plain "and".
  static bool _newStatement(String clause) {
    final String folded = foldTemporalCase(clause);
    return _subject.hasMatch(
      folded.substring(ClauseSplitter.taskStartIn(folded)),
    );
  }

  static final RegExp _subject = RegExp(r'^(?:i|we)\b');

  /// Whether [next] names a day other than the one [plan] is on: "so today
  /// buy the cable" after "the electrician is coming tomorrow".
  bool _hasDayOfItsOwn(String next, ParsedWhen plan, LocalDateTime now) {
    final ParsedWhen own = parser.parse(next, now: now);
    return own.dateSpoken && (!plan.dateSpoken || own.date != plan.date);
  }

  /// [task] with the time of a clause that only says when it happens, or
  /// null when that time does not fit: the task has a time already, the clause
  /// names a day of its own, or the time on the task's day has passed.
  ///
  /// ⚠️ Only for a task with a day. "Cook dinner, my husband is coming home
  /// at 7" said at 15:00 has no day to put the 7 on, and the bare 7 alone
  /// rolls to 07:00 tomorrow — a dinner at breakfast time.
  static ExtractedTask? _timed(
    ExtractedTask task,
    ParsedWhen when,
    LocalDateTime now,
  ) {
    final LocalTimeOfDay? time = when.time;
    final LocalDate? date = task.date;
    if (time == null || date == null || when.dateSpoken || task.time != null) {
      return null;
    }
    if (LocalDateTime(date, time).isBefore(now)) return null;
    return task.copyWith(time: time, hasReminder: true);
  }

  /// Whether [folded] only says when the task titled [title] happens: "the
  /// flight is at 6" after "Fly to Seoul", "it's at noon".
  ///
  /// ⚠️ Only when the task is the thing itself — a trip, a meeting, an event.
  /// "Tomorrow iron my shirt, my interview is at 10" is two things: the
  /// interview at 10, and the shirt at any time before it. Merged, the
  /// interview was lost and the ironing was set for 10.
  static bool _elaborates(String folded, String title) {
    final RegExpMatch? match = _elaboration.firstMatch(folded);
    if (match == null) return false;
    if (match[1] == null) return true;
    final String lower = foldTemporalCase(title);
    if (_attendance.hasMatch(lower)) return true;
    final List<String> words = RegExp(r"[a-z][a-z']*")
        .allMatches(lower)
        .map((RegExpMatch m) => m[0]!)
        .take(3)
        .toList();
    return words.isNotEmpty &&
        !ClauseLexicon.isImperativeVerb(words.first) &&
        words.any(ClauseLexicon.isEventNoun);
  }

  /// A task that is going somewhere or being at something: "Fly to Seoul",
  /// "Go to the dentist", "Take Sevara to the pediatrician", "Meet Sardor".
  static final RegExp _attendance = RegExp(
    r'^(?:(?:go|fly|drive|travel|ride|head|come|walk|attend|visit|meet)\b'
    r'|(?:take|bring)\b.*\bto\b)',
  );

  /// Folds a "remind me (when)" into the task it is about.
  ///
  /// The reminder's when fills whatever the task does not already have: all of
  /// it for "Call Anna. Remind me tomorrow at 9.", only the time for "Pay rent
  /// on Friday. Remind me at 9.". A task that already has both keeps them.
  static ExtractedTask _withReminder(ExtractedTask task, ParsedWhen when) {
    if (task.date == null && task.time == null && !when.isEmpty) {
      return ExtractedTask(
        title: task.title,
        date: when.date,
        time: when.time,
        hasReminder: true,
        confidence: when.confidence,
        whenText: task.whenText,
      );
    }
    if (task.time == null && when.time != null && !when.dateSpoken) {
      return task.copyWith(hasReminder: true, time: when.time);
    }
    return task.copyWith(hasReminder: true);
  }

  /// [task] with the reminder a "remind me the day before (at 9)" asks for:
  /// [days] before its day, at the time said or, with none, the all-day hour.
  ///
  /// ⚠️ A task carries one moment and its reminder fires then, so a to-do
  /// moves to the moment the user asked to be told: done a day early it is
  /// still done, and a reminder that fires a day late is found out only when
  /// it is too late. Only a to-do, though — a task that opens with what to
  /// do. An event is fixed in time whether or not it has a clock time ("the
  /// exam is on Monday", "Wedding on October 10th"), and so is a deadline
  /// ("the rent is due on the 1st"): moved, the card misstates the day of
  /// the exam, the wedding, the payment. Nor a task with no day to count back
  /// from, nor one whose reminder would already be past. Those only get the
  /// reminder.
  static ExtractedTask _remindedEarlier(
    ExtractedTask task,
    String taskClause,
    ParsedWhen when,
    int days,
    LocalDateTime now,
  ) {
    final LocalDate? due = task.date;
    final String opening = wordAfter(foldTemporalCase(task.title), 0);
    final bool toDo =
        (ClauseLexicon.isImperativeVerb(opening) ||
            ClauseLexicon.isLeadingOnlyVerb(opening)) &&
        !ClauseLexicon.isEventNoun(opening) &&
        !_deadline.hasMatch(foldTemporalCase(taskClause));
    if (due == null || task.time != null || !toDo) {
      return task.copyWith(hasReminder: true);
    }
    final LocalDate day = due.addDays(-days);
    final LocalTimeOfDay? time = when.time;
    final LocalDateTime at = LocalDateTime(
      day,
      time ?? const LocalTimeOfDay(ExtractionDefaults.allDayReminderMinute),
    );
    if (at.isBefore(now)) return task.copyWith(hasReminder: true);
    return ExtractedTask(
      title: task.title,
      date: day,
      time: time,
      hasReminder: true,
      confidence: task.confidence,
      whenText: task.whenText,
    );
  }

  /// Whether every when of [clause] is said between "remind me" and the
  /// first "to" after it: "Remind me at 7 pm to take my pills" — not "remind
  /// me to call Nargiza at 4", whose 4 is the call's alone.
  static bool _saidBeforeTheTo(String clause, ParsedWhen when) {
    if (when.spans.isEmpty) return false;
    final RegExpMatch? m = _remindMeThenTo.firstMatch(foldTemporalCase(clause));
    if (m == null) return false;
    final int start = m.start + m[0]!.indexOf(m[1]!, 'remind'.length);
    final int end = start + m[1]!.length;
    return when.spans.every(
      (MatchSpan span) => span.start >= start && span.end <= end,
    );
  }

  static final RegExp _remindMeThenTo = RegExp(
    r'\bremind\s+(?:me|us)\s+((?:(?!\bto\b)[^,;])+?)\s+to\s+[a-z]',
  );

  /// "to lock the garage", "and to buy balloons".
  static final RegExp _toInfinitive = RegExp(r'^\s*(?:and\s+)?to\s+[a-z]');

  /// "the rent is due…", "the deadline for the essay is…".
  static final RegExp _deadline = RegExp(r'\b(?:due|deadline)\b');

  /// "the day before", "two days before", "the evening before", "a week in
  /// advance" — how long before the task the reminder is wanted.
  ///
  /// ⚠️ Not "the day before the exam": what it is before is named there, and
  /// read as this, the exam was a second card.
  static final RegExp _remindEarlier = RegExp(
    r'\b(?:(?:the|a|one)\s+(day|evening|night|week)'
    r'|(\d|two|three|four|five|six|seven)\s+(days|weeks))'
    r'\s+(?:before|earlier|in\s+advance|ahead)\b'
    r'(?!\s+(?:the|a|an|my|our|his|her|their|this|that)\b)',
  );

  static int _daysEarlier(RegExpMatch match) {
    final String unit = match[1] ?? match[3]!;
    final int count = match[1] != null
        ? 1
        : int.tryParse(match[2]!) ?? _counts[match[2]!]!;
    return unit.startsWith('week') ? count * 7 : count;
  }

  static const Map<String, int> _counts = <String, int>{
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
  };

  /// Whether the clause names something to do or attend: a verb a task
  /// starts with, or an event ("the meeting", "the dentist").
  static bool _hasAction(String clause) =>
      RegExp(r"[a-z][a-z']*")
          .allMatches(clause.toLowerCase())
          .any(
            (RegExpMatch m) =>
                ClauseLexicon.isImperativeVerb(m[0]!) ||
                ClauseLexicon.isEventNoun(m[0]!),
          );

  /// "by Friday", "before the 25th", "due on…" — a deadline, not the day
  /// the rest of the note is about.
  bool _isDeadline(String clause, ParsedWhen when) {
    if (when.spans.isEmpty) return false;
    final String before = clause
        .substring(0, when.spans.first.start.clamp(0, clause.length))
        .toLowerCase()
        .trimRight();
    final String said = (_whenTextOf(clause, when) ?? '').toLowerCase();
    return RegExp(r'\b(?:by|before|until|till|due)$').hasMatch(before) ||
        RegExp(r'^(?:by|before|until|till|due)\b').hasMatch(said);
  }

  /// Whether the when is the first thing the clause says: "Tomorrow buy…",
  /// "Um, so, on Monday I have to…" — not "Buy it tomorrow".
  static bool _isFronted(String clause, ParsedWhen when) {
    if (when.spans.isEmpty) return false;
    final String before = foldTemporalCase(
      clause.substring(0, when.spans.first.start.clamp(0, clause.length)),
    );
    return RegExp(r"[a-z']+")
        .allMatches(before)
        .every((RegExpMatch m) => ClauseLexicon.isDiscourseWord(m[0]!));
  }

  static final RegExp _relative = RegExp(r'^in\b', caseSensitive: false);

  /// A condition on something the speaker waits for: somebody else acting
  /// ("when Aziz sends the documents", "once they approve the loan"), a
  /// thing coming or being done ("once it arrives", "once it's fixed"), the
  /// pay coming in ("after payday", "when the salary comes", "when I get
  /// paid"). The task is on that day, which nobody said.
  ///
  /// ⚠️ Not the speaker's own day — "when I get home", "after work", "after
  /// that" — nor what happens on the occasion itself: "when he answers ask
  /// about the deposit", "when the shop opens buy bread". Nor a question
  /// put to somebody: "ask when she arrives".
  static final RegExp _awaitsEvent = RegExp(
    r'(?<!\b(?:ask|asks|check|know|see|tell\s+me|find\s+out|figure\s+out'
    r'|remember|decide|confirm|wonder)\s)'
    r'\b(?:once|as\s+soon\s+as|when|whenever|after|until|till)\s+'
    r"(?!(?:i|we|you|i'm|we're|you're|that|this|then|there)\b)"
    r"(?:it|he|she|they|(?:the|my|his|her|our|their|your)\s+[a-z']+"
    r"|[a-z']+)"
    r'(?:\s+(?:comes|come|arrives|arrive|sends|send|calls|call|replies|reply'
    r'|pays|pay|returns|return|approves|approve|confirms|confirm|delivers'
    r'|deliver|brings|bring|transfers|transfer|signs|sign|writes|write|texts'
    r'|text|emails|email|lands|land|gets\s+back|get\s+back)'
    r"|(?:'s|'re|\s+is|\s+are|\s+gets|\s+get)\s+(?:fixed|ready|done|back"
    r'|repaired|delivered|finished|paid|approved|signed|sent|available|here'
    r'|free|in))\b'
    r'|\b(?:after|once|when|until|till|before)\s+(?:(?:the|my|next|his|her'
    r'|our)\s+)?(?:payday|pay\s+day|salary|paycheck|paycheque|pension|bonus)\b'
    r'|\b(?:once|when|after)\s+(?:i|we)\s+(?:get|got)\s+paid\b',
  );

  /// "oh" opening a clause, past its "and" and any hesitation.
  static final RegExp _afterthought = RegExp(
    '^[\\s,]*(?:(?:and|${ClauseLexicon.hesitations})[\\s,]+)*oh\\b',
  );

  /// The joints that say the next thing follows on the same occasion.
  static const Set<String> _sequence = <String>{
    SplitClause.and,
    'then',
    'and then',
    'after that',
  };

  /// "the flight is at 6", "my job interview is at 10", "it's at noon" — a
  /// definite thing and a copula, then only the time. The thing, when there is
  /// one, is the group.
  static final RegExp _elaboration = RegExp(
    '^(?:(?:${ClauseLexicon.hesitations}|so|and|oh|okay)[\\s,]+)*'
    r'(?:(?:the|its|his|her|my|our|their)\s+((?:[a-z]+\s+){0,2}[a-z]+)'
    r"|it|that)(?:\s+is|'s|\s+will\s+be|\s+starts)\s+(?:at|around|about|from)"
    r'\s',
  );

  /// "both on Friday", "all of them tomorrow" — ⚠️ not a bare "all": in
  /// "call them all on Friday" it belongs to the object.
  static final RegExp _distributive = RegExp(
    r'\b(?:both(?:\s+of\s+them)?|(?:all|each)\s+of\s+(?:them|these)),?\s+'
    r'(?:on|by|at|in|for|this|next|tomorrow|today|tonight)\b',
  );

  static bool _saidMeridiem(String clause) => RegExp(
    r'\d\s*[ap]\.?\s?m\b|\b[ap]\.m\b',
    caseSensitive: false,
  ).hasMatch(clause);

  static LocalTimeOfDay _toEvening(LocalTimeOfDay time) =>
      time.minuteOfDay < 12 * 60
      ? LocalTimeOfDay(time.minuteOfDay + (12 * 60))
      : time;

  static final RegExp _evening = RegExp(
    r'\b(?:tonight|evening|night)\b',
    caseSensitive: false,
  );

  static final RegExp _night = RegExp(
    r'\b(?:tonight|night)\b',
    caseSensitive: false,
  );

  static final RegExp _sentenceEnd = RegExp(r'[.!?]\s*$');

  /// A spoken time is a request to be told; a bare date is not. "Remind me"
  /// says so outright.
  bool _wantsReminder(String clause, ParsedWhen when) =>
      when.time != null || _remindWords.hasMatch(clause);

  /// The words the date came from, kept so the Confirm card can explain itself
  /// and so a wrong answer drops straight into the corpus as one line.
  String? _whenTextOf(String clause, ParsedWhen when) {
    if (when.isEmpty || when.spans.isEmpty) return null;
    final String text = when.spans
        .map(
          (MatchSpan span) => clause.substring(
            span.start.clamp(0, clause.length),
            span.end.clamp(0, clause.length),
          ),
        )
        .join(' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  static final RegExp _remindWords = RegExp(
    r'\b(remind|reminder|alarm|alert|nudge)\b',
    caseSensitive: false,
  );
}
