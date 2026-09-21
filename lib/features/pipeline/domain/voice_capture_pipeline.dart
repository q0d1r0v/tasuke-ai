import 'dart:async';
import 'dart:typed_data';

import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';
import 'package:tasuke_ai/features/pipeline/domain/amplitude_track.dart';
import 'package:tasuke_ai/features/tasks/domain/task.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

/// The outcome of one capture attempt, as the controller sees it.
sealed class CaptureOutcome {
  const CaptureOutcome();
}

final class CaptureDrafts extends CaptureOutcome {
  const CaptureDrafts(this.drafts, {required this.transcript});

  final List<TaskDraft> drafts;
  final String transcript;
}

final class CaptureRejected extends CaptureOutcome {
  const CaptureRejected(this.failure);

  final Failure failure;
}

/// The engine behind the Recording → Processing → Confirm flow.
///
/// Deliberately framework-free: it takes ports, not providers, so the whole
/// pipeline runs in a plain `test()` with fakes. The Riverpod controller in
/// `presentation/` is a thin shell around this.
final class VoiceCapturePipeline {
  VoiceCapturePipeline({
    required this._recorder,
    required this._recognizer,
    required TaskExtractor primaryExtractor,
    required TaskExtractor fallbackExtractor,
    required this._permissions,
    required this._usage,
    required this._clock,
    required this._newDraftId,
    this._maxDuration = ExtractionDefaults.maxRecordingDuration,
    this._minDuration = ExtractionDefaults.minRecordingDuration,
  }) : _primary = primaryExtractor,
       _fallback = fallbackExtractor;

  final AudioRecorder _recorder;
  final SpeechRecognizer _recognizer;
  final TaskExtractor _primary;
  final TaskExtractor _fallback;
  final PermissionService _permissions;
  final UsageRepository _usage;
  final Clock _clock;
  final String Function() _newDraftId;
  final Duration _maxDuration;
  final Duration _minDuration;

  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<SpeechEvent>? _speechSub;
  Timer? _ticker;
  Completer<String>? _transcriptCompleter;
  DateTime? _startedAt;
  bool _cancelled = false;
  bool _hitLimit = false;

  /// The waveform's data source. Owned here so the recorder's chunks feed it
  /// directly rather than travelling through the state object.
  final AmplitudeTrack amplitude = AmplitudeTrack();

  final ElapsedTrack elapsed = ElapsedTrack();

  bool get hitRecordingLimit => _hitLimit;

  /// Checks the free quota **before** anything is recorded.
  ///
  /// ⚠️ Order matters: a refusal here must happen before the microphone opens,
  /// so a user who is out of quota does not see a recording UI they cannot use,
  /// and no audio is captured that will be thrown away.
  Future<Failure?> checkQuota({required bool isPro}) async {
    if (isPro) return null;
    final LocalDate today = LocalDate.today(_clock.nowLocal());
    final DailyUsage usage = await _usage.read(today);
    if (usage.captureCount >= ExtractionDefaults.freeDailyCaptures) {
      return QuotaFailure(
        'Daily voice capture limit reached',
        used: usage.captureCount,
        limit: ExtractionDefaults.freeDailyCaptures,
      );
    }
    return null;
  }

  /// Requests the microphone. Returns null when it is usable.
  Future<Failure?> ensureMicrophone() async {
    PermissionState state = await _permissions.status(AppPermission.microphone);
    if (state == PermissionState.notDetermined ||
        state == PermissionState.denied) {
      state = await _permissions.request(AppPermission.microphone);
    }
    if (state.isGranted) return null;
    return PermissionFailure(
      'Microphone permission not granted',
      permanentlyDenied: state.needsSettings,
    );
  }

  /// Opens the microphone and begins streaming into the recogniser.
  ///
  /// [onPartial] fires with each revised transcript so the Recording screen can
  /// show words as they land.
  Future<Failure?> startRecording({
    required void Function(String partial) onPartial,
    required void Function() onAutoStop,
  }) async {
    _cancelled = false;
    _hitLimit = false;
    amplitude.reset();
    elapsed.reset();

    final SpeechAvailability availability = await _recognizer.availability();
    if (availability != SpeechAvailability.ready) {
      return TranscriptionFailure(
        'Speech model unavailable',
        kind: availability == SpeechAvailability.modelUnavailable
            ? TranscriptionFailureKind.modelUnavailable
            : TranscriptionFailureKind.unknown,
      );
    }

    final Stream<Uint8List> raw;
    try {
      raw = await _recorder.start();
    } on Object catch (error, stack) {
      Log.e('recorder failed to start', error, stack);
      return const RecordingFailure(
        'Could not start recording',
        kind: RecordingFailureKind.busy,
      );
    }

    // One source of audio, two consumers: the waveform and the recogniser.
    // A broadcast controller rather than `asBroadcastStream()` so that a late
    // recogniser subscription cannot drop the first chunks.
    final StreamController<Uint8List> fanout =
        StreamController<Uint8List>.broadcast();

    _audioSub = raw.listen(
      (Uint8List chunk) {
        amplitude.addChunk(chunk);
        if (!fanout.isClosed) fanout.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        Log.e('audio stream error', error, stack);
        if (!fanout.isClosed) fanout.addError(error, stack);
      },
      onDone: () {
        if (!fanout.isClosed) unawaited(fanout.close());
      },
      cancelOnError: false,
    );

    final Completer<String> completer = Completer<String>();
    _transcriptCompleter = completer;

    // The most recent revision, kept so a session that ends without finalising
    // does not throw away words that were already heard.
    String lastPartial = '';

    _speechSub = _recognizer
        .transcribeStream(fanout.stream)
        .listen(
          (SpeechEvent event) {
            switch (event) {
              case SpeechPartial(:final String text):
                lastPartial = text;
                onPartial(text);
              case SpeechFinal(:final String text):
                if (!completer.isCompleted) completer.complete(text);
              case SpeechAmplitude(:final double level):
                amplitude.addLevel(level);
              case SpeechError():
                break;
            }
          },
          onError: (Object error, StackTrace stack) {
            Log.e('transcription stream error', error, stack);
            if (!completer.isCompleted) completer.completeError(error, stack);
          },
          onDone: () {
            // Whisper closes without a final event in two cases: the audio was
            // nothing but silence, and inference gave up part-way through.
            // ⚠️ Fall back to the last revision rather than to the empty
            // string — silence revised nothing, so this is still '' there, but
            // an aborted utterance keeps what was heard. Words the user has to
            // say again are worse than a slightly short transcript, which is
            // the contract SpeechError states.
            if (!completer.isCompleted) completer.complete(lastPartial);
          },
          cancelOnError: false,
        );

    _startedAt = _clock.nowLocal();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (Timer timer) {
      final DateTime? started = _startedAt;
      if (started == null) return;
      final Duration value = _clock.nowLocal().difference(started);
      elapsed.value = value;
      if (value >= _maxDuration) {
        _hitLimit = true;
        timer.cancel();
        onAutoStop();
      }
    });

    return null;
  }

  Duration get recordedDuration {
    final DateTime? started = _startedAt;
    if (started == null) return Duration.zero;
    return _clock.nowLocal().difference(started);
  }

  /// Stops the microphone, waits for the final transcript, and returns it.
  ///
  /// Returns a [RecordingFailure] when the clip is too short to be speech, so
  /// the caller can keep the user on the Recording screen instead of pushing
  /// them through a pipeline that will find nothing.
  Future<Object> stopRecording() async {
    final Duration duration = recordedDuration;
    if (!_hitLimit && duration < _minDuration) {
      // ⚠️ The microphone is released here too, not merely unsubscribed from.
      // `_teardown` only cancels this object's subscriptions; the recorder and
      // the speech session keep running. The real recorder then throws
      // `RecordingFailure(busy)` from the *next* `start()`, so a mis-tap on the
      // mic would brick capture for the rest of the process — and the OS
      // recording indicator would stay lit the whole time.
      try {
        await _recorder.cancel();
        await _recognizer.cancel();
      } on Object catch (error, stack) {
        Log.e('releasing after a too-short clip failed', error, stack);
      } finally {
        await _teardown();
      }
      return const RecordingFailure(
        'Recording too short',
        kind: RecordingFailureKind.tooShort,
      );
    }

    try {
      await _recorder.stop();
      await _recognizer.stop();
      final String transcript =
          await (_transcriptCompleter?.future ?? Future<String>.value(''));
      return transcript.trim();
    } on Object catch (error, stack) {
      Log.e('stopRecording failed', error, stack);
      return const TranscriptionFailure('Transcription failed');
    } finally {
      await _teardown();
    }
  }

  /// Runs extraction over a finished transcript.
  Future<CaptureOutcome> extract(String transcript) async {
    if (transcript.trim().isEmpty) {
      return const CaptureRejected(
        TranscriptionFailure(
          'No speech detected',
          kind: TranscriptionFailureKind.noSpeech,
        ),
      );
    }

    final LocalDateTime now = LocalDateTime.fromLocal(_clock.nowLocal());

    // The language model is preferred, but it may still be downloading. The
    // deterministic extractor is not a degraded mode in that case — it is the
    // reason the app is usable at all on first launch.
    TaskExtractor extractor = _fallback;
    try {
      if (await _primary.isReady()) extractor = _primary;
    } on Object catch (error, stack) {
      Log.e('extractor readiness check failed', error, stack);
    }

    List<ExtractedTask> extracted;
    try {
      extracted = await extractor
          .extract(transcript, now: now)
          .timeout(ExtractionDefaults.extractionTimeout);
    } on TimeoutException {
      // A timeout on the model is not a dead end: the rule-based extractor is
      // microseconds and produces something the user can edit.
      Log.w('extraction timed out; falling back to the rule-based extractor');
      try {
        extracted = await _fallback.extract(transcript, now: now);
      } on Object catch (error, stack) {
        Log.e('fallback extraction failed', error, stack);
        extracted = const <ExtractedTask>[];
      }
    } on Object catch (error, stack) {
      Log.e('extraction failed', error, stack);
      try {
        extracted = await _fallback.extract(transcript, now: now);
      } on Object catch (error2, stack2) {
        Log.e('fallback extraction failed', error2, stack2);
        extracted = const <ExtractedTask>[];
      }
    }

    // ⚠️ Zero tasks is never a dead end. The user spoke; discarding what they
    // said and asking them to say it again is the single most frustrating thing
    // this app could do. Hand them the raw transcript as one editable draft.
    if (extracted.isEmpty) {
      return CaptureDrafts(<TaskDraft>[
        TaskDraft(
          draftId: _newDraftId(),
          title: TaskTitle.normalise(transcript),
          sourceTranscript: transcript,
        ),
      ], transcript: transcript);
    }

    final List<TaskDraft> drafts = <TaskDraft>[
      for (final ExtractedTask task in extracted)
        TaskDraft(
          draftId: _newDraftId(),
          title: task.title,
          date: task.date,
          time: task.time,
          hasReminder: task.hasReminder,
          sourceTranscript: transcript,
          lowConfidenceDate: task.confidence == Confidence.low,
        ),
    ];

    return CaptureDrafts(drafts, transcript: transcript);
  }

  /// Records one **successful** capture against the daily quota.
  ///
  /// ⚠️ Called only after tasks are saved. A capture that hit silence, failed
  /// to transcribe or was cancelled must not consume quota — that is the
  /// complaint users actually file.
  Future<void> recordUsage({required int taskCount}) async {
    final LocalDate today = LocalDate.today(_clock.nowLocal());
    await _usage.recordCapture(today, taskCount: taskCount);
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _recorder.cancel();
      await _recognizer.cancel();
    } on Object catch (error, stack) {
      Log.e('cancel failed', error, stack);
    } finally {
      await _teardown();
    }
  }

  bool get wasCancelled => _cancelled;

  /// Frees the speech model from native memory. Called when the capture flow
  /// closes, not between phases — reloading a 57 MB model per capture is
  /// several seconds the user watches.
  Future<void> releaseModel() => _recognizer.release();

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _speechSub?.cancel();
    _speechSub = null;
    _startedAt = null;
  }

  Future<void> dispose() async {
    await _teardown();
    amplitude.dispose();
    elapsed.dispose();
  }
}
