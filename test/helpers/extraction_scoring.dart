import 'dart:convert';
import 'dart:io';

import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';

/// One labelled note: what a person would write down after hearing it.
final class LabelledNote {
  const LabelledNote(this.note, this.expected);

  final String note;
  final List<ExpectedTask> expected;
}

/// `'*'` in [date] or [time] accepts anything: the note really is ambiguous.
final class ExpectedTask {
  const ExpectedTask(this.title, this.date, this.time);

  final String title;
  final String? date;
  final String? time;
}

/// Loads a corpus written by hand or by `extraction_heldout_corpus.json`.
({LocalDateTime now, List<LabelledNote> notes}) loadLabelledCorpus(
  String path,
) => parseLabelledCorpus(File(path).readAsStringSync());

/// The same, from the JSON text itself — for a device, which cannot read the
/// repo's fixtures.
({LocalDateTime now, List<LabelledNote> notes}) parseLabelledCorpus(
  String json,
) {
  final Map<String, Object?> doc = jsonDecode(json) as Map<String, Object?>;
  final String nowIso = (doc['now'] as String?) ?? '2026-09-21T10:00';
  final List<LabelledNote> notes = <LabelledNote>[];
  for (final Object? raw in doc['cases']! as List<Object?>) {
    final Map<String, Object?> item = raw! as Map<String, Object?>;
    notes.add(
      LabelledNote(item['note']! as String, <ExpectedTask>[
        for (final Object? t in item['tasks']! as List<Object?>)
          _expectedOf(t! as Map<String, Object?>),
      ]),
    );
  }
  return (now: LocalDateTime.parseIso(nowIso), notes: notes);
}

ExpectedTask _expectedOf(Map<String, Object?> t) => ExpectedTask(
  t['title']! as String,
  t['date'] as String?,
  t['time'] as String?,
);

/// The words that carry a title's meaning, stemmed to four letters so
/// "mountains"/"mountain" and "prepare"/"preparing" agree.
Set<String> contentWords(String text) =>
    RegExp(r"[a-z0-9']+")
        .allMatches(text.toLowerCase())
        .map((Match m) => m[0]!.replaceAll("'s", '').replaceAll("'", ''))
        .where((String w) => w.isNotEmpty && !_stop.contains(w))
        .map((String w) => w.length > 4 ? w.substring(0, 4) : w)
        .toSet();

double titleSimilarity(String a, String b) {
  final Set<String> x = contentWords(a);
  final Set<String> y = contentWords(b);
  if (x.isEmpty && y.isEmpty) return 1;
  final int both = x.intersection(y).length;
  return both / x.union(y).length;
}

const Set<String> _stop = <String>{
  'a',
  'an',
  'the',
  'to',
  'my',
  'for',
  'with',
  'of',
  'and',
  'at',
  'on',
  'in',
  'i',
  'me',
  'it',
  'some',
  'up',
  'from',
  'about',
  'his',
  'her',
  'our',
  'your',
  'their',
  'this',
  'that',
  'him',
  'them',
  'go',
  'do',
  'get',
};

/// The outcome of one note.
final class NoteScore {
  NoteScore(this.note, this.expected, this.actual);

  final LabelledNote note;
  final List<ExpectedTask> expected;
  final List<ExtractedTask> actual;

  int matched = 0;
  int datesChecked = 0;
  int datesRight = 0;
  int timesChecked = 0;
  int timesRight = 0;
  final List<String> problems = <String>[];

  bool get exact =>
      matched == expected.length &&
      actual.length == expected.length &&
      datesRight == datesChecked &&
      timesRight == timesChecked;
}

NoteScore scoreNote(LabelledNote note, List<ExtractedTask> actual) {
  final NoteScore s = NoteScore(note, note.expected, actual);
  final Set<int> used = <int>{};
  for (final ExpectedTask want in note.expected) {
    int best = -1;
    double bestSim = 0;
    for (int i = 0; i < actual.length; i++) {
      if (used.contains(i)) continue;
      final double sim = titleSimilarity(want.title, actual[i].title);
      if (sim > bestSim) {
        bestSim = sim;
        best = i;
      }
    }
    if (best < 0 || bestSim < 0.5) {
      s.problems.add('missing "${want.title}"');
      continue;
    }
    used.add(best);
    s.matched++;
    final ExtractedTask got = actual[best];
    if (want.date != '*') {
      s.datesChecked++;
      final String? gotDate = got.date?.toIso();
      if (gotDate == want.date) {
        s.datesRight++;
      } else {
        s.problems.add('"${got.title}" date $gotDate, want ${want.date}');
      }
    }
    if (want.time != '*') {
      s.timesChecked++;
      final String? gotTime = got.time?.toIso();
      if (gotTime == want.time) {
        s.timesRight++;
      } else {
        s.problems.add('"${got.title}" time $gotTime, want ${want.time}');
      }
    }
  }
  for (int i = 0; i < actual.length; i++) {
    if (!used.contains(i)) s.problems.add('extra "${actual[i].title}"');
  }
  return s;
}

/// Totals over a corpus, printable as one line.
final class Scorecard {
  Scorecard(this.name, this.scores);

  final String name;
  final List<NoteScore> scores;

  int get _expected =>
      scores.fold(0, (int a, NoteScore s) => a + s.expected.length);
  int get _actual =>
      scores.fold(0, (int a, NoteScore s) => a + s.actual.length);
  int get _matched => scores.fold(0, (int a, NoteScore s) => a + s.matched);
  int _sum(int Function(NoteScore) f) =>
      scores.fold(0, (int a, NoteScore s) => a + f(s));

  double get recall => _expected == 0 ? 1 : _matched / _expected;
  double get precision => _actual == 0 ? 1 : _matched / _actual;
  double get dateAccuracy {
    final int n = _sum((NoteScore s) => s.datesChecked);
    return n == 0 ? 1 : _sum((NoteScore s) => s.datesRight) / n;
  }

  double get timeAccuracy {
    final int n = _sum((NoteScore s) => s.timesChecked);
    return n == 0 ? 1 : _sum((NoteScore s) => s.timesRight) / n;
  }

  double get exactRate =>
      scores.where((NoteScore s) => s.exact).length / scores.length;

  String summary() =>
      '$name: exact ${(exactRate * 100).round()}% · '
      'recall ${(recall * 100).round()}% · '
      'precision ${(precision * 100).round()}% · '
      'dates ${(dateAccuracy * 100).round()}% · '
      'times ${(timeAccuracy * 100).round()}% · n=${scores.length}';

  String details() => <String>[
    for (final NoteScore s in scores)
      if (!s.exact) '✗ ${s.note.note}\n    ${s.problems.join('; ')}',
  ].join('\n');
}
