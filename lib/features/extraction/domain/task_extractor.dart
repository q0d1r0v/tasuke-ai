import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'extracted_task.dart';

/// Turns a transcript into tasks.
///
/// Takes `now` rather than reading a clock, which is what lets the fixture
/// table hold a hundred cases as one-liners.
abstract interface class TaskExtractor {
  /// Whether this extractor can run — the language model may still be
  /// downloading.
  Future<bool> isReady();

  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  });
}
