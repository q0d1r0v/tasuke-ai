import 'package:tasuke_ai/core/time/local_date_time.dart';

import 'clause_splitter.dart';
import 'extracted_task.dart';
import 'extraction_defaults.dart';
import 'task_extractor.dart';
import 'title_cleaner.dart';
import 'when_parser.dart';

/// The extractor that needs no language model.
///
/// It runs while the model is still downloading, and it is what the pipeline
/// tests measure against — every case it gets right is a case the model is not
/// allowed to get wrong.
final class RuleBasedTaskExtractor implements TaskExtractor {
  const RuleBasedTaskExtractor({
    this.splitter = const ClauseSplitter(),
    this.parser = const WhenParser(),
    this.cleaner = const TitleCleaner(),
  });

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
    for (final String clause in splitter.splitClauses(transcript)) {
      if (tasks.length >= ExtractionDefaults.maxTasksPerCapture) break;
      final ParsedWhen when = parser.parse(clause, now: now);
      String title = cleaner.clean(
        clause,
        matchStart: when.matchStart,
        matchEnd: when.matchEnd,
        spans: when.spans,
      );
      if (title.isEmpty) {
        // "Tomorrow at three" with no verb at all. Keeping the words the user
        // said beats dropping the capture on the floor — the Confirm screen is
        // where they fix it.
        title = cleaner.clean(clause, matchStart: 0, matchEnd: 0);
      }
      if (title.isEmpty) continue;
      tasks.add(
        ExtractedTask(
          title: title,
          date: when.date,
          time: when.time,
          hasReminder: _wantsReminder(clause, when),
          confidence: when.confidence,
          whenText: _whenTextOf(clause, when),
        ),
      );
    }
    return tasks;
  }

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
