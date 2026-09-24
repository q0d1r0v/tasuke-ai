import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/core/time/local_time_of_day.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';

/// A transcript longer than [ExtractionDefaults.inlineExtractionChars] is read
/// on an isolate of its own, so that a whisper repetition loop cannot freeze
/// the UI. It must read exactly as it would inline.
void main() {
  const RuleBasedTaskExtractor extractor = RuleBasedTaskExtractor();
  final LocalDateTime now = LocalDateTime.parseIso('2026-09-24T11:00');

  test('a long transcript reads the same off the calling isolate', () async {
    final String note =
        'Call Anna tomorrow at 5. ${'Thank you. ' * 50}Buy milk tonight.';
    expect(note.length, greaterThan(ExtractionDefaults.inlineExtractionChars));

    final List<ExtractedTask> tasks = await extractor.extract(note, now: now);

    expect(
      <String>[for (final ExtractedTask t in tasks) t.title],
      <String>['Call Anna', 'Buy milk'],
    );
    expect(tasks.first.date, const LocalDate(2026, 9, 25));
    expect(tasks.first.time, LocalTimeOfDay.hm(17, 0));
    expect(tasks.last.date, const LocalDate(2026, 9, 24));
  });

  test('a run of hesitations does not blow up the restart rule', () async {
    // ⚠️ With an ambiguous gap after each "um", 24 of them took five seconds
    // and every two more took four times as long — on the UI isolate, since
    // the note is short.
    final String note = 'So, ${'um ' * 30}call Anna tomorrow.';
    final Stopwatch watch = Stopwatch()..start();
    final List<ExtractedTask> tasks = await extractor.extract(note, now: now);
    expect(tasks.single.title, 'Call Anna');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a whisper loop of corrections still ends, and quickly', () async {
    final String loop = 'Call Anna ${'at 5, no, 6, ' * 80}please.';
    final Stopwatch watch = Stopwatch()..start();
    final List<ExtractedTask> tasks = await extractor.extract(loop, now: now);
    expect(tasks, isNotEmpty);
    expect(watch.elapsed, lessThan(ExtractionDefaults.extractionTimeout));
  });
}
