import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';

import '../../helpers/extraction_scoring.dart';

/// How well the rule-based extractor turns real speech into tasks.
///
/// ⚠️ Two corpora, kept apart on purpose. The development set is what the
/// rules were tuned against; the held-out set was written separately, by
/// people who never saw the rules, and is the honest number. A change that
/// lifts the first and drops the second is overfitting, not progress.
void main() {
  Future<Scorecard> score(String name, String path) async {
    final corpus = loadLabelledCorpus(path);
    final List<NoteScore> scores = <NoteScore>[];
    for (final LabelledNote note in corpus.notes) {
      final List<ExtractedTask> tasks = await const RuleBasedTaskExtractor()
          .extract(note.note, now: corpus.now);
      scores.add(scoreNote(note, tasks));
    }
    return Scorecard(name, scores);
  }

  // Floors a little under today's scores (dev 100 %, held-out 97 %, fresh
  // 97 %), so a rule that helps one phrasing and quietly breaks three others
  // fails here instead of on a phone. The honest number is the fresh set
  // BEFORE anyone looked at it: 75 %. Raise the floors when the scores rise;
  // never lower one to make a change pass.
  //
  // The complex sets — run-ons, hard whens, casual speech — have floors of
  // their own. ⚠️ Their held-out half is the honest one: 40 % exact before the
  // rules were tuned on the dev half, 57 % after (dev: 37 % → 100 %), 60 %
  // after the fixes from the second review, 63 % after the review of those
  // fixes. Its per-note failures are not for reading while tuning — only its
  // summary.
  for (final _Corpus corpus in <_Corpus>[
    const _Corpus('dev', 'test/fixtures/nl/extraction_dev_corpus.json', 0.95),
    const _Corpus(
      'held-out',
      'test/fixtures/nl/extraction_heldout_corpus.json',
      0.9,
    ),
    const _Corpus(
      'fresh',
      'test/fixtures/nl/extraction_fresh_corpus.json',
      0.9,
    ),
    // Every case here was a real bug an adversarial review reproduced; each
    // must stay fixed, so the floor is all of them.
    const _Corpus(
      'review regressions',
      'test/fixtures/nl/extraction_review_regressions.json',
      1,
    ),
    const _Corpus(
      'complex dev',
      'test/fixtures/nl/extraction_complex_dev_corpus.json',
      0.95,
    ),
    // Today: exact 63 %, recall 91 %, precision 89 %, dates 97 %, times 95 %.
    const _Corpus(
      'complex held-out',
      'test/fixtures/nl/extraction_complex_heldout_corpus.json',
      0.6,
      recall: 0.88,
      precision: 0.86,
      dates: 0.94,
      times: 0.92,
    ),
    // Correctly typed notes the whisper-tolerance rules once damaged —
    // amounts read as clock times, a film title split in two, a past tense
    // turned into an order, a name lower-cased (2026-09-23 review). Every
    // case must stay exact, so the floor is all of them on every line.
    const _Corpus(
      'correct-input guard',
      'test/fixtures/nl/extraction_correct_input_guard.json',
      1,
      recall: 1,
      precision: 1,
      dates: 1,
      times: 1,
    ),
    // The same thirty notes typed and as whisper writes them, from the same
    // review, never used to write a rule before it. Before the fixes, on the
    // labels corrected to the conventions ("tonight" is 20:00): typed 80 %
    // exact, whisper-style 77 %. Today both are 100 % on every line; the
    // floors leave one note of slack.
    const _Corpus(
      'typed pairs',
      'test/fixtures/nl/extraction_typed_pairs_corpus.json',
      0.96,
      recall: 0.97,
      precision: 0.97,
      dates: 0.97,
      times: 0.97,
    ),
    const _Corpus(
      'whisper-style pairs',
      'test/fixtures/nl/extraction_whisper_style_corpus.json',
      0.96,
      recall: 0.97,
      precision: 0.97,
      dates: 0.97,
      times: 0.97,
    ),
  ]) {
    test('rule-based extraction quality — ${corpus.name}', () async {
      if (!File(corpus.path).existsSync()) {
        markTestSkipped('${corpus.path} not present');
        return;
      }
      final Scorecard card = await score(corpus.name, corpus.path);
      // ignore: avoid_print
      print('${card.summary()}\n${card.details()}');
      expect(
        card.exactRate,
        greaterThanOrEqualTo(corpus.exact),
        reason: card.details(),
      );
      expect(
        card.recall,
        greaterThanOrEqualTo(corpus.recall),
        reason: card.details(),
      );
      expect(
        card.precision,
        greaterThanOrEqualTo(corpus.precision),
        reason: card.details(),
      );
      expect(card.dateAccuracy, greaterThanOrEqualTo(corpus.dates));
      expect(card.timeAccuracy, greaterThanOrEqualTo(corpus.times));
    });
  }
}

/// A corpus and the scores it may not fall below.
final class _Corpus {
  const _Corpus(
    this.name,
    this.path,
    this.exact, {
    this.recall = 0.95,
    this.precision = 0.95,
    this.dates = 0.95,
    this.times = 0.95,
  });

  final String name;
  final String path;
  final double exact;
  final double recall;
  final double precision;
  final double dates;
  final double times;
}
