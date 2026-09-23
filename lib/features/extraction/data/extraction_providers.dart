import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';

/// What the pipeline tries first: the rule-based extractor.
///
/// ⚠️ Decided by measurement, not taste. An on-device language model
/// (LFM2-350M-Extract, through llama.cpp) was built into the app, measured
/// against the labelled corpora in `test/fixtures/nl/` and then removed. Whole
/// note exact, on a set written after the rules were tuned and never used to
/// tune them:
///
///   rule-based            75 % on the unseen set before it was looked at,
///                         95–100 % on the sets it was tuned against
///   LFM2-350M-Extract     32 % held-out, with its best prompt, greedy
///                         decoding and every post-filter
///
/// The model's failures were the ones a user feels as "unstable": it answered
/// with the prompt's own worked example for about two notes in three, invented
/// times that were never said ("Clean the house" → tomorrow 15:00), missed the
/// second and third task in a sentence, and gave a different answer to the
/// same sentence on each try. It also cost native libraries in every build and
/// a 219 MB download. The rule-based extractor is deterministic, cannot invent
/// a word the user did not say, and answers in microseconds.
///
/// `extraction_quality_test.dart` holds the floor. Anything proposed as a
/// replacement has to beat it on the held-out corpus, not on a demo sentence.
final Provider<TaskExtractor> primaryTaskExtractorProvider =
    Provider<TaskExtractor>((Ref ref) => const RuleBasedTaskExtractor());

/// What the pipeline falls back to when the primary is not ready, throws or
/// times out.
///
/// The same deterministic extractor as the primary: there is no better second
/// opinion to fall back to, and a failure there is a bug to fix, not a flaky
/// answer to retry. The seam stays because tests override each side on its own
/// to drive the pipeline's fallback path.
final Provider<TaskExtractor> fallbackTaskExtractorProvider =
    Provider<TaskExtractor>((Ref ref) => const RuleBasedTaskExtractor());
