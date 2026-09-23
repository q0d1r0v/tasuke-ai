import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/notification_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/features/capture/domain/capture_phase.dart';
import 'package:tasuke_ai/features/extraction/data/extraction_providers.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
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

/// How long a new capture waits for the last one to hand the microphone and
/// the speech model back before giving up with "still finishing".
///
/// ⚠️ Sized for a whole final pass, not one decode. A session cancelled after
/// Stop cannot be interrupted: whisper runs its full-context final pass, which
/// the pipeline itself allows up to [ExtractionDefaults.transcriptionTimeout],
/// and only then lets go. At 10 s, Stop, back out of Processing and tap the
/// mic again on a slow phone failed with "Your microphone is in use" while
/// nothing but the app's own decode was running. A teardown still running
/// after this is wedged, and opening the microphone on top of it would only
/// fight it.
final Duration _teardownBudget =
    ExtractionDefaults.transcriptionTimeout + const Duration(seconds: 5);

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

  /// Which session the state belongs to. Bumped by each [begin], [cancel] and
  /// [reset].
  ///
  /// ⚠️ Every `await` below re-checks it. Nothing used to, so a Stop or a slow
  /// extraction that finished after the user had cancelled wrote its result
  /// over `idle`: the next mic tap opened Confirm with the discarded tasks, or
  /// found `failed` on Home and did nothing at all.
  int _generation = 0;

  /// Set while [begin] is opening the microphone. [stop] holds a tap until it
  /// is open (there is nothing to stop yet), and a [cancel] waits for it to
  /// finish so it can release what was opened.
  Completer<void>? _opening;

  /// The generation whose Stop was tapped while [_opening] was set.
  ///
  /// ⚠️ Kept, not dropped. The phase is already `recording`, so the Stop
  /// button is on screen and enabled; a tap it silently ate left the user
  /// talking to a recording they had asked to end.
  int? _stopTappedWhileOpening;

  /// The last session's teardown — a cancel, or the model release after a
  /// save — if it is still running. The next [begin] waits for it: opening a
  /// microphone and a whisper session while the old ones are still being
  /// handed back is two sessions fighting over one set of native state.
  Future<void>? _teardown;

  /// Whether a [begin] now would first have to wait for [_teardown].
  ///
  /// The Recording screen reads it to name that wait ("Finishing your last
  /// recording first"). The mic button learns of the wait through [begin]'s
  /// `onWait` instead: it otherwise navigates only once [begin] returns, and a
  /// tap that waited out a final pass looked like a tap that did nothing.
  bool get isTearingDown => _teardown != null;

  /// Exposed for the Recording screen's waveform and timer, which listen to
  /// these directly rather than rebuilding on every sample.
  AmplitudeTrack get amplitude => _pipeline.amplitude;

  ElapsedTrack get elapsed => _pipeline.elapsed;

  /// Entry point from the mic button.
  ///
  /// Returns the location to navigate to, or null when the caller should stay
  /// put (the state already carries the failure to render). A spent quota
  /// returns [PaywallReason.quota]'s location, so the paywall can say why it
  /// is up.
  ///
  /// [onWait] runs when the quota is fine but the last capture is still
  /// tearing down, just before [begin] starts waiting for it — the mic button
  /// puts "Getting ready" on screen then, and only then.
  Future<String?> begin({void Function()? onWait}) async {
    // ⚠️ Not for `failed`: nothing is in flight once a capture has failed, and
    // `captureLocationFor(failed)` is null — a failure left behind on Home
    // made the mic button do nothing, for good.
    if (state.phase.isActive && state.phase != CapturePhase.failed) {
      return captureLocationFor(state.phase);
    }

    final int generation = ++_generation;
    state = const CaptureState(phase: CapturePhase.checkingQuota);
    // ⚠️ Now, not when the microphone opens. Nothing between sessions clears
    // them, and "Getting ready" can sit on screen for a whole final pass of
    // the last capture: it showed that capture's frozen length and waveform,
    // as if the recording the user had just thrown away were still running.
    // Safe: past the early return above no recording is live to be cleared,
    // and `startRecording` clears both again anyway.
    _pipeline.amplitude.reset();
    _pipeline.elapsed.reset();

    // ⚠️ The quota BEFORE the wait for the last capture, not after it. It is a
    // database read and needs neither the microphone nor the model. Checked
    // after, a wait that ran out ended in "still closing", whose "Type a task
    // instead" let a user who had spent the day's capture save a second one;
    // and a user out of quota sat through a whole final pass only to be shown
    // the paywall. Once is enough: a save records its usage before it queues
    // its teardown, so nothing the wait covers can use up the quota.
    final bool isPro = ref.read(isProProvider);
    final Failure? quota = await _pipeline.checkQuota(isPro: isPro);
    if (generation != _generation) return null;
    if (quota != null) {
      state = CaptureState.idle;
      return PaywallReason.quota.location;
    }

    final Future<void>? previous = _teardown;
    if (previous != null) {
      onWait?.call();
      bool settled = true;
      await previous.timeout(
        _teardownBudget,
        onTimeout: () {
          settled = false;
        },
      );
      if (generation != _generation) return null;
      if (!settled) {
        Log.w('the last capture is still tearing down; not opening the mic');
        state = state.copyWith(
          phase: CapturePhase.failed,
          failure: const RecordingFailure(
            'The last capture is still closing',
            kind: RecordingFailureKind.stillClosing,
          ),
        );
        return AppRoute.capture.path;
      }
    }

    state = state.copyWith(phase: CapturePhase.requestingPermission);
    final Failure? permission = await _pipeline.ensureMicrophone();
    if (generation != _generation) return null;
    if (permission != null) {
      state = state.copyWith(phase: CapturePhase.failed, failure: permission);
      return AppRoute.capture.path;
    }

    state = state.copyWith(phase: CapturePhase.recording, clearFailure: true);

    final Completer<void> opening = Completer<void>();
    _opening = opening;
    final Failure? started;
    try {
      started = await _pipeline.startRecording(
        onPartial: (String partial) {
          // Only while recording: a partial that lands after Stop would
          // overwrite the final transcript.
          if (generation == _generation &&
              state.phase == CapturePhase.recording) {
            state = state.copyWith(transcript: partial);
          }
        },
        onAutoStop: () {
          if (generation == _generation) unawaited(stop());
        },
      );
    } finally {
      if (identical(_opening, opening)) _opening = null;
      opening.complete();
    }
    final bool stopTapped = _stopTappedWhileOpening == generation;
    if (stopTapped) _stopTappedWhileOpening = null;
    // Cancelled while the microphone was opening. That cancel waited for
    // `opening` and is releasing whatever was opened.
    if (generation != _generation) return null;
    if (started != null) {
      state = state.copyWith(phase: CapturePhase.failed, failure: started);
    } else if (stopTapped) {
      unawaited(stop());
    }
    return AppRoute.capture.path;
  }

  /// Stop → transcribe → extract → confirm.
  Future<void> stop() async {
    if (state.phase != CapturePhase.recording) return;
    if (_opening != null) {
      // [begin] carries it out the moment the microphone is open.
      _stopTappedWhileOpening = _generation;
      return;
    }
    final int generation = _generation;
    state = state.copyWith(phase: CapturePhase.transcribing);

    final Object result = await _pipeline.stopRecording();
    // Cancelled while whisper finalised: this belongs to a discarded capture.
    if (generation != _generation) return;
    if (result is Failure) {
      // ⚠️ `failed` for every arm, including a clip too short to be speech.
      //
      // By now the router has moved the user on to Processing, which has no
      // error UI; for `failed` the guard sends them back to the Recording
      // screen, which reads "Hold on — say a bit more" with a Try again that
      // re-opens the mic. An earlier version set `idle` here instead,
      // reasoning that the recorder was already torn down; but
      // `captureLocationFor(idle)` is null, the guard turns that into a bounce
      // to Home, and a user who released Stop half a second early was silently
      // thrown out of the capture flow with no message at all.
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
    if (generation != _generation) return;
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
    final int generation = _generation;
    state = state.copyWith(phase: CapturePhase.extracting, clearFailure: true);
    final CaptureOutcome outcome = await _pipeline.extract(transcript);
    if (generation != _generation) return;
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
    final int generation = _generation;
    final List<TaskDraft> drafts = state.drafts;
    state = state.copyWith(phase: CapturePhase.saving, clearFailure: true);

    final List<Task> saved;
    try {
      final int allDayMinute =
          (await ref.read(settingsRepositoryProvider).read())
              .allDayReminderMinute;

      saved = await ref
          .read(taskRepositoryProvider)
          .saveDrafts(
            drafts,
            captureId: _uuid.v4(),
            allDayReminderMinute: allDayMinute,
          );
    } on Object catch (error, stack) {
      Log.e('saving drafts failed', error, stack);
      if (generation == _generation) {
        state = state.copyWith(
          phase: CapturePhase.confirming,
          failure: StorageFailure(
            'Could not save',
            diskFull:
                error.toString().contains('disk') ||
                error.toString().contains('full'),
          ),
        );
      }
      return false;
    }

    // ⚠️ The tasks are committed from here on, so nothing below may send the
    // flow back to Confirm. When the usage write after them failed, the
    // screen said "Could not save" over saved tasks, and the retry saved every
    // one of them a second time, reminders and all.

    // Usage is recorded only now: one save is one capture, spoken or typed —
    // the free allowance counts both (a product decision, 2026-09-23). A
    // capture that hit silence, failed or was cancelled saved nothing and
    // consumes nothing.
    try {
      await _pipeline.recordUsage(taskCount: saved.length);
    } on Object catch (error, stack) {
      // One missed quota tick is the lesser harm, and it errs the user's way.
      Log.e('recording usage after a save failed', error, stack);
    }

    // ⚠️ Ask for the notification permission HERE, before the sweep — the
    // moment the user has just asked for a reminder. Onboarding's primer is
    // skippable, and a user who skipped it had every reminder silently
    // dropped. Awaited so the sweep below sees the answer; the sweep itself
    // stays detached.
    if (saved.any((Task task) => task.reminder.enabled)) {
      try {
        await ensureReminderPermissions(
          ref.read(permissionServiceProvider),
          alreadyPrompted: () => ref.read(exactAlarmPromptedProvider),
          markPrompted: ref.read(exactAlarmPromptedProvider.notifier).complete,
        );
      } on Object catch (error, stack) {
        // A permission plugin that throws must not un-save the tasks.
        Log.e('asking for the notification permission failed', error, stack);
      }
    }

    unawaited(ref.read(reminderSchedulerProvider).sync());
    unawaited(_enqueueTeardown(_pipeline.releaseModel));

    if (generation == _generation) {
      state = CaptureState(savedCount: saved.length);
    }
    return true;
  }

  /// Ends the session. Idle at once; the teardown runs after.
  ///
  /// ⚠️ Idle FIRST, before anything is awaited. The pipeline's teardown can
  /// take seconds — whisper finishes a model load or a decode before it lets
  /// go — and while it ran the phase stayed `recording`: Stop and Cancel both
  /// still worked, and a Stop tapped then brought the cancelled capture back.
  /// Idle now also lets the router take the user Home straight away.
  ///
  /// The returned future is the teardown, for a caller that wants to wait.
  Future<void> cancel() {
    final Future<void>? pending = _teardown;
    // A second tap while the first cancel is still tearing down.
    if (pending != null && state.phase == CapturePhase.idle) return pending;

    _generation++;
    state = CaptureState.idle;

    final VoiceCapturePipeline pipeline = _pipeline;
    final Future<void>? opening = _opening?.future;
    return _enqueueTeardown(() async {
      if (opening != null) await opening;
      await pipeline.cancel();
      await pipeline.releaseModel();
    });
  }

  /// Clears a failure without leaving the flow, so an error screen's "Try
  /// again" returns to a usable Recording screen.
  void reset() {
    _generation++;
    state = CaptureState.idle;
  }

  /// Runs [work] after any teardown already queued, and keeps it in
  /// [_teardown] until it is done. Never throws.
  Future<void> _enqueueTeardown(Future<void> Function() work) {
    Future<void> run() async {
      try {
        await work();
      } on Object catch (error, stack) {
        Log.e('tearing a capture down failed', error, stack);
      }
    }

    final Future<void>? previous = _teardown;
    final Future<void> next = previous == null
        ? run()
        : previous.then((_) => run());
    _teardown = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_teardown, next)) _teardown = null;
      }),
    );
    return next;
  }
}
