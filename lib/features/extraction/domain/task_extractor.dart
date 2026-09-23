import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'extracted_task.dart';

/// Turns a transcript into tasks.
///
/// Takes `now` rather than reading a clock, which is what lets the fixture
/// table hold a hundred cases as one-liners.
abstract interface class TaskExtractor {
  /// Whether this extractor can run right now.
  ///
  /// The pipeline asks before every extraction and uses its fallback on false
  /// or on a throw. The rule-based extractor is always ready; the question
  /// stays on the port so an extractor that needs setup cannot be handed a
  /// transcript before it can answer.
  Future<bool> isReady();

  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  });
}
