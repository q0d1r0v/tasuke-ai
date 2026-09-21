import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/data/llm_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_json_validator.dart';
import 'package:tasuke_ai/features/extraction/domain/rule_based_task_extractor.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';

/// The validator, as the function [LlmTaskExtractor] asks for.
///
/// This adapter is the only place the model adapter and the domain validator
/// meet. `null` means "did not survive validation", which is what makes the
/// extractor's one retry a plain null check rather than a second vocabulary of
/// rejection reasons that it would have nothing useful to do with.
List<ExtractedTask>? parseExtractorOutput(
  String raw, {
  required LocalDateTime now,
}) {
  final ValidationResult result = const ExtractionJsonValidator().validate(
    raw,
    now: now,
  );
  if (result.isRejected) {
    // The reason is content-free by construction — see ValidationResult.reason.
    Log.w('extractor output rejected: ${result.rejection} ${result.reason}');
    return null;
  }
  return result.tasks;
}

/// The language-model extractor.
///
/// Exposed as its concrete type so the app can dispose it; nothing else should
/// depend on the class.
final Provider<LlmTaskExtractor>
llmTaskExtractorProvider = Provider<LlmTaskExtractor>((Ref ref) {
  final LlmTaskExtractor extractor = LlmTaskExtractor(
    // `read`, not `watch`, and resolved per call: a download that finishes
    // mid-session is then picked up on the next capture instead of rebuilding
    // the provider and throwing away a loaded engine.
    modelPath: () => ref.read(extractorModelPathProvider.future),
    parse: parseExtractorOutput,
  );
  ref.onDispose(() => unawaited(extractor.dispose()));
  return extractor;
});

/// What the pipeline tries first.
final Provider<TaskExtractor> primaryTaskExtractorProvider =
    Provider<TaskExtractor>((Ref ref) => ref.watch(llmTaskExtractorProvider));

/// What the pipeline falls back to.
///
/// Not "the degraded path": it runs for every user for as long as the 219 MB
/// download takes, and it is the only extractor a user who declines the
/// download will ever have. It needs no model and no disposal, which is why it
/// is a `const`.
final Provider<TaskExtractor> fallbackTaskExtractorProvider =
    Provider<TaskExtractor>((Ref ref) => const RuleBasedTaskExtractor());
