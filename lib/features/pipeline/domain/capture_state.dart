import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

/// Everything the three capture screens render.
final class CaptureState {
  const CaptureState({
    this.phase = CapturePhase.idle,
    this.transcript = '',
    this.drafts = const <TaskDraft>[],
    this.failure,
    this.elapsed = Duration.zero,
    this.truncatedAtLimit = false,
    this.savedCount = 0,
  });

  static const CaptureState idle = CaptureState();

  final CapturePhase phase;

  /// The live transcript. Whisper revises earlier words as more audio arrives,
  /// so this is replaced wholesale, never appended to.
  final String transcript;

  final List<TaskDraft> drafts;
  final Failure? failure;
  final Duration elapsed;

  /// True when recording stopped because it hit the one-minute cap rather than
  /// because the user did. The Confirm screen says so.
  final bool truncatedAtLimit;

  final int savedCount;

  bool get hasDrafts => drafts.isNotEmpty;

  bool get allDraftsValid =>
      drafts.isNotEmpty && drafts.every((TaskDraft d) => d.isValid);

  CaptureState copyWith({
    CapturePhase? phase,
    String? transcript,
    List<TaskDraft>? drafts,
    Failure? failure,
    Duration? elapsed,
    bool? truncatedAtLimit,
    int? savedCount,
    bool clearFailure = false,
  }) => CaptureState(
    phase: phase ?? this.phase,
    transcript: transcript ?? this.transcript,
    drafts: drafts ?? this.drafts,
    failure: clearFailure ? null : (failure ?? this.failure),
    elapsed: elapsed ?? this.elapsed,
    truncatedAtLimit: truncatedAtLimit ?? this.truncatedAtLimit,
    savedCount: savedCount ?? this.savedCount,
  );

  @override
  bool operator ==(Object other) =>
      other is CaptureState &&
      other.phase == phase &&
      other.transcript == transcript &&
      other.drafts == drafts &&
      other.failure == failure &&
      other.elapsed == elapsed &&
      other.truncatedAtLimit == truncatedAtLimit &&
      other.savedCount == savedCount;

  @override
  int get hashCode => Object.hash(
    phase,
    transcript,
    drafts,
    failure,
    elapsed,
    truncatedAtLimit,
    savedCount,
  );
}

/// Which row of the Processing checklist is lit.
enum ProcessingStep { transcribe, understand, find, finish }
