import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/pipeline/domain/amplitude_track.dart';
import 'package:tasuke_ai/features/pipeline/domain/capture_state.dart';
import 'package:tasuke_ai/features/pipeline/domain/voice_capture_pipeline.dart';
import 'package:tasuke_ai/features/reminders/data/reminder_providers.dart';
import 'package:tasuke_ai/features/settings/data/settings_providers.dart';
import 'package:tasuke_ai/features/tasks/data/task_providers.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';
import 'package:uuid/uuid.dart';

export 'package:tasuke_ai/features/pipeline/domain/capture_state.dart';

const Uuid _uuid = Uuid();

/// Assembles the pipeline from the ports. Kept separate from the controller so
/// a test can override just this and leave every other provider alone.
final Provider<VoiceCapturePipeline> voiceCapturePipelineProvider =
    Provider<VoiceCapturePipeline>((Ref ref) {
      final VoiceCapturePipeline pipeline = VoiceCapturePipeline(
        recorder: ref.watch(audioRecorderProvider),
        recognizer: ref.watch(speechRecognizerProvider),
        primaryExtractor: ref.watch(primaryTaskExtractorProvider),
        fallbackExtractor: ref.watch(fallbackTaskExtractorProvider),
        permissions: ref.watch(permissionServiceProvider),
        usage: ref.watch(usageRepositoryProvider),
        clock: ref.watch(clockProvider),
        newDraftId: () => _uuid.v4(),
      );
      ref.onDispose(() => unawaited(pipeline.dispose()));
      return pipeline;
    });

final NotifierProvider<CaptureController, CaptureState>
captureControllerProvider = NotifierProvider<CaptureController, CaptureState>(
  CaptureController.new,
);

/// Drives Recording → Processing → Confirm.
///
/// It only ever advances a phase; the router decides which screen that phase
/// puts on screen (see `_redirect` in `app_router.dart`).
final class CaptureController extends Notifier<CaptureState> {
  @override
  CaptureState build() => CaptureState.idle;

  VoiceCapturePipeline get _pipeline => ref.read(voiceCapturePipelineProvider);

  /// Exposed for the Recording screen's waveform and timer, which listen to
  /// these directly rather than rebuilding on every sample.
  AmplitudeTrack get amplitude => _pipeline.amplitude;

  ElapsedTrack get elapsed => _pipeline.elapsed;

  /// Entry point from the mic button.
  ///
  /// Returns the location to navigate to, or null when the caller should stay
  /// put (the state already carries the failure to render).
  Future<String?> begin() async {
    if (state.phase.isActive) return captureLocationFor(state.phase);

    state = const CaptureState(phase: CapturePhase.checkingQuota);

    final bool isPro = ref.read(isProProvider);
    final Failure? quota = await _pipeline.checkQuota(isPro: isPro);
    if (quota != null) {
      state = CaptureState.idle;
      return AppRoute.paywall.path;
    }

    state = state.copyWith(phase: CapturePhase.requestingPermission);
    final Failure? permission = await _pipeline.ensureMicrophone();
    if (permission != null) {
      state = state.copyWith(phase: CapturePhase.failed, failure: permission);
      return AppRoute.capture.path;
    }

    state = state.copyWith(phase: CapturePhase.recording, clearFailure: true);

    final Failure? started = await _pipeline.startRecording(
      onPartial: (String partial) {
        // Only while recording: a partial that lands after Stop would overwrite
        // the final transcript.
        if (state.phase == CapturePhase.recording) {
          state = state.copyWith(transcript: partial);
        }
      },
      onAutoStop: () => unawaited(stop()),
    );
    if (started != null) {
      state = state.copyWith(phase: CapturePhase.failed, failure: started);
    }
    return AppRoute.capture.path;
  }

  /// Stop → transcribe → extract → confirm.
  Future<void> stop() async {
    if (state.phase != CapturePhase.recording) return;
    state = state.copyWith(phase: CapturePhase.transcribing);

    final Object result = await _pipeline.stopRecording();
    if (result is Failure) {
      // ⚠️ `failed` for every arm, including a clip too short to be speech.
      //
      // `failed` is the only phase the router leaves alone — `_redirect`
      // returns early for it — so the user stays on the Recording screen and
      // reads "Hold on — say a bit more" with a Try again that re-opens the
      // mic. An earlier version set `idle` here instead, reasoning that the
      // recorder was already torn down; but `captureLocationFor(idle)` is
      // null, the guard turns that into a bounce to Home, and a user who
      // released Stop half a second early was silently thrown out of the
      // capture flow with no message at all.
      state = state.copyWith(phase: CapturePhase.failed, failure: result);
      return;
    }

    final String transcript = result as String;
    state = state.copyWith(
      phase: CapturePhase.extracting,
      transcript: transcript,
      truncatedAtLimit: _pipeline.hitRecordingLimit,
    );

    final CaptureOutcome outcome = await _pipeline.extract(transcript);
    switch (outcome) {
      case CaptureRejected(:final Failure failure):
        state = state.copyWith(phase: CapturePhase.failed, failure: failure);
      case CaptureDrafts(:final List<TaskDraft> drafts):
        state = state.copyWith(
          phase: CapturePhase.confirming,
          drafts: drafts,
          clearFailure: true,
        );
    }
  }

  /// Re-runs extraction on the transcript already in hand.
  ///
  /// Worth its own entry point: after an extraction failure the user should not
  /// have to say it all again when the words were understood perfectly well.
  Future<void> retryExtraction() async {
    final String transcript = state.transcript;
    if (transcript.isEmpty) return;
    state = state.copyWith(phase: CapturePhase.extracting, clearFailure: true);
    final CaptureOutcome outcome = await _pipeline.extract(transcript);
    switch (outcome) {
      case CaptureRejected(:final Failure failure):
        state = state.copyWith(phase: CapturePhase.failed, failure: failure);
      case CaptureDrafts(:final List<TaskDraft> drafts):
        state = state.copyWith(phase: CapturePhase.confirming, drafts: drafts);
    }
  }

  /// Opens Confirm with one blank draft — the "type a task instead" escape
  /// from every capture failure, and the reason no failure is a dead end.
  void startManualDraft() {
    state = CaptureState(
      phase: CapturePhase.confirming,
      drafts: <TaskDraft>[
        TaskDraft(draftId: _uuid.v4(), title: '', source: TaskSource.manual),
      ],
    );
  }

  void updateDraft(TaskDraft draft) {
    state = state.copyWith(
      drafts: <TaskDraft>[
        for (final TaskDraft d in state.drafts)
          if (d.draftId == draft.draftId) draft else d,
      ],
    );
  }

  void removeDraft(String draftId) {
    state = state.copyWith(
      drafts: state.drafts
          .where((TaskDraft d) => d.draftId != draftId)
          .toList(growable: false),
    );
  }

  void addBlankDraft() {
    state = state.copyWith(
      drafts: <TaskDraft>[
        ...state.drafts,
        TaskDraft(
          draftId: _uuid.v4(),
          title: '',
          source: TaskSource.manual,
          sourceTranscript: state.transcript.isEmpty ? null : state.transcript,
        ),
      ],
    );
  }

  /// Persists the drafts and schedules their reminders.
  ///
  /// Returns true on success. On failure the drafts are **kept** — a failed
  /// save that also ate the user's edits is the worst possible outcome.
  Future<bool> save() async {
    if (!state.allDraftsValid) return false;
    state = state.copyWith(phase: CapturePhase.saving, clearFailure: true);

    try {
      final int allDayMinute =
          (await ref.read(settingsRepositoryProvider).read())
              .allDayReminderMinute;

      final List<Task> saved = await ref
          .read(taskRepositoryProvider)
          .saveDrafts(
            state.drafts,
            captureId: _uuid.v4(),
            allDayReminderMinute: allDayMinute,
          );

      // Usage is recorded only now, and only for a voice capture. A capture
      // that hit silence, failed or was cancelled must not consume quota.
      final bool cameFromVoice = state.drafts.any(
        (TaskDraft d) => d.source == TaskSource.voice,
      );
      if (cameFromVoice) {
        await _pipeline.recordUsage(taskCount: saved.length);
      }

      unawaited(ref.read(reminderSchedulerProvider).sync());
      unawaited(_pipeline.releaseModel());

      state = CaptureState(savedCount: saved.length);
      return true;
    } on Object catch (error, stack) {
      Log.e('saving drafts failed', error, stack);
      state = state.copyWith(
        phase: CapturePhase.confirming,
        failure: StorageFailure(
          'Could not save',
          diskFull:
              error.toString().contains('disk') ||
              error.toString().contains('full'),
        ),
      );
      return false;
    }
  }

  Future<void> cancel() async {
    await _pipeline.cancel();
    unawaited(_pipeline.releaseModel());
    state = CaptureState.idle;
  }

  /// Clears a failure without leaving the flow, so an error screen's "Try
  /// again" returns to a usable Recording screen.
  void reset() {
    state = CaptureState.idle;
  }
}
