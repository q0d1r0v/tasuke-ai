import 'dart:async';
import 'dart:typed_data';

import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/speech/whisper_decoding.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Removes whisper's non-speech annotations from a transcript.
///
/// whisper does not stay silent about what it did not understand: it writes
/// `[BLANK_AUDIO]` for a quiet tail, `(speaking in foreign language)` for
/// speech outside the model's language, `[MUSIC]`, `(laughing)`, and so on.
/// Left in, those become task titles — a user who said nothing useful got a
/// task called "(speaking in foreign language)", and an English note picked up
/// a trailing "[BLANK_AUDIO]" that the date parser then had to step around.
///
/// Stripped, an all-annotation transcript is simply empty, which the pipeline
/// already turns into "We didn't catch that" without spending a capture.
///
/// ⚠️ Bracketed and parenthesised spans are removed wholesale. That is safe
/// here and would not be in general: base.en uses those delimiters only for
/// annotations, and nobody dictates parentheses into a to-do.
String stripNonSpeech(String text) => text
    .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
    .replaceAll(RegExp(r'\([^)]*\)'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// On-device speech-to-text, through the vendored whisper.cpp binding.
///
/// The one importer of `package:whisper_ggml`. Everything above it holds a
/// [SpeechRecognizer], which is what lets the capture pipeline be pumped in a
/// test on a machine with no microphone and no native library.
final class WhisperSpeechRecognizer implements SpeechRecognizer {
  WhisperSpeechRecognizer({
    required this._modelAsset,
    WhisperController? controller,
    this._micAvailable,
    this._decoding = WhisperDecoding.app,
  }) : _controller = controller ?? WhisperController();

  /// How whisper is primed: [WhisperDecoding.app] unless a test asks otherwise.
  final WhisperDecoding _decoding;

  final WhisperModelAsset _modelAsset;
  final WhisperController _controller;

  /// Injected rather than asked of `record` directly: this file may not import a
  /// second plugin, and "is there a microphone" is a question the recorder and
  /// the permission service already answer between them.
  final Future<bool> Function()? _micAvailable;

  /// The latest [transcribeStream] call. [stop] and [cancel] act on it.
  _Run? _current;

  @override
  Future<void> prepare() async {
    // Failures are swallowed on purpose: [availability] is the place that
    // reports "no model", and it re-checks the filesystem itself. Throwing here
    // would take down the launch path for a condition the capture screen
    // already explains and offers a retry for.
    try {
      await _modelAsset.ensureInstalled();
    } on Object catch (error, stack) {
      Log.e('installing the bundled speech model failed', error, stack);
    }
  }

  @override
  Future<SpeechAvailability> availability() async {
    if (await _modelAsset.pathIfInstalled() == null) {
      return SpeechAvailability.modelUnavailable;
    }
    final Future<bool> Function()? mic = _micAvailable;
    if (mic != null && !await mic()) {
      return SpeechAvailability.microphoneUnavailable;
    }
    return SpeechAvailability.ready;
  }

  /// Consumes PCM16 and emits partials, then one [SpeechFinal].
  ///
  /// No [SpeechAmplitude] is emitted, even though the port allows it. The level
  /// comes from `RecordAudioRecorder.levels`, computed once where the bytes
  /// arrive; a second RMS over the same chunks would give the waveform two
  /// slightly different truths depending on which stream it subscribed to.
  @override
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16) {
    final StreamController<SpeechEvent> out = StreamController<SpeechEvent>();
    final _Run? previous = _current;
    final _Run run = _Run();
    _current = run;
    out.onListen = () => unawaited(_run(run, pcm16, out, previous));
    // ⚠️ Not awaited. The pipeline's teardown awaits its subscription's
    // cancel(), and that future is whatever onCancel returns: returning the
    // cancel itself made the bounded 30 s wait for a slow or wedged session
    // unbounded again. `VoiceCapturePipeline.cancel` awaits [cancel] directly.
    out.onCancel = () => unawaited(_cancelRun(run));
    return out.stream;
  }

  Future<void> _run(
    _Run run,
    Stream<Uint8List> pcm16,
    StreamController<SpeechEvent> out,
    _Run? previous,
  ) async {
    run.started = true;
    StreamSubscription<String>? partials;
    try {
      final String? modelPath = await _modelAsset.pathIfInstalled();
      if (run.cancelled) return;
      if (modelPath == null) {
        throw const TranscriptionFailure(
          'The whisper model is not on disk',
          kind: TranscriptionFailureKind.modelUnavailable,
        );
      }

      // The audio actually handed to the binding.
      //
      // The caller's stream is **not** passed straight through. Interposing a
      // controller buys two things that are awkward otherwise: this class
      // learns when input ended (the binding's `stop()` is the only way to read
      // the final transcript, and calling it early truncates the recording),
      // and `stop()` becomes "close the feed" rather than "reach into someone
      // else's stream".
      final StreamController<Uint8List> feed = StreamController<Uint8List>();
      run.feed = feed;

      // ⚠️ Subscribed to the microphone BEFORE the model is loaded, not after.
      //
      // `transcribeLive` below takes seconds to map a 60 MB ggml model, and
      // whatever the user says in that window has to go somewhere. `feed` is a
      // single-subscription controller, so bytes added now queue in it and are
      // delivered in order the instant the binding attaches its own listener.
      // Starting this after the await instead is how the opening words of every
      // recording get lost — and the adapter has to be right about this on its
      // own, whatever the caller hands it.
      run.audio = pcm16.listen(
        (Uint8List bytes) {
          if (!feed.isClosed) feed.add(bytes);
        },
        onDone: run.closeFeed,
        onError: (Object error, StackTrace stack) {
          Log.e('audio stream error during transcription', error, stack);
          run.closeFeed();
        },
      );
      // ⚠️ Stop came before the feed existed. Not closed right away: the
      // source replays its buffer one microtask per chunk, and closing now
      // dropped the whole recording. A timer runs after those, and still ends
      // a source that never closes on its own.
      if (run.stopRequested) Timer.run(run.closeFeed);

      // ⚠️ One native session at a time. The whisper stream is a process-wide
      // singleton, so a session still finishing — one the pipeline gave up
      // waiting for — would run its stop against this one's window.
      if (previous != null && previous.started) await previous.done.future;
      if (run.cancelled) return;

      // `keepModelLoaded: true` parks the model in native memory when the
      // session stops. Loading base.en costs several seconds; a user who
      // records twice in a row would otherwise pay it twice. `release()` gives
      // the memory back.
      final WhisperLiveSession session = await _controller.transcribeLive(
        modelPath: modelPath,
        pcm16Stream: feed.stream,
        keepModelLoaded: true,
        initialPrompt: _decoding.initialPrompt,
        promptOnPreviews: _decoding.promptOnPreviews,
      );
      run.session = session;
      if (run.cancelled) {
        await session.abort();
        return;
      }

      partials = session.partials.listen(
        (String text) {
          if (!out.isClosed) out.add(SpeechPartial(stripNonSpeech(text)));
        },
        // A mid-session native error arrives here and is then followed by
        // whatever text the binding kept, so it is logged rather than
        // forwarded: failing the stream would throw away a usable transcript.
        onError: (Object error, StackTrace stack) =>
            Log.e('whisper partial error', error, stack),
      );

      // ⚠️ Wait for the binding to have taken ALL the audio before touching
      // `stop()`. The binding's `stop()` both finalises *and* terminates; any
      // chunk still queued in `feed` behind it is dropped, and after a Stop
      // during the model load that was most of the recording.
      await run.drained.future;
      // After a cancel this is [WhisperLiveSession.abort]'s future: no pass.
      final String text = await session.stop();

      if (run.cancelled) return;
      final String spoken = stripNonSpeech(text);
      if (spoken.isEmpty) {
        throw const TranscriptionFailure(
          'Nothing was said',
          kind: TranscriptionFailureKind.noSpeech,
        );
      }
      if (!out.isClosed) out.add(SpeechFinal(spoken));
    } on TranscriptionFailure catch (failure, stack) {
      if (!run.cancelled && !out.isClosed) out.addError(failure, stack);
    } on Object catch (error, stack) {
      Log.e('transcription failed', error, stack);
      if (!run.cancelled && !out.isClosed) {
        out.addError(const TranscriptionFailure('Transcription failed'), stack);
      }
    } finally {
      run.closeFeed();
      await partials?.cancel();
      await run.audio?.cancel();
      run.audio = null;
      run.session = null;
      if (!run.done.isCompleted) run.done.complete();
      if (!out.isClosed) await out.close();
    }
  }

  /// Returns at once. The transcript follows on the stream once the binding
  /// has taken the rest of the audio, which after a Stop during the model load
  /// is after the load. The pipeline bounds that wait; this must not block it.
  @override
  Future<void> stop() async {
    _current?.closeFeed();
  }

  @override
  Future<void> cancel() => _cancelRun(_current);

  Future<void> _cancelRun(_Run? run) async {
    if (run == null) return;
    run.cancelled = true;
    // ⚠️ Abort BEFORE the feed closes. Closing it runs the binding's onDone,
    // which is `stop()`: a full-context decode — seconds on a phone — of audio
    // that is about to be thrown away. Abort still hands the native context
    // and the worker back; it only skips that pass. A session still loading
    // is aborted by [_run] the moment it exists.
    final WhisperLiveSession? session = run.session;
    unawaited(session?.abort());
    await run.audio?.cancel();
    run.audio = null;
    if (session != null) run.closeFeed();
    // Until the run has let go of the native session: `release()` frees the
    // model right after this, and a context still in use cannot be freed.
    if (run.started) await run.done.future;
  }

  @override
  Future<void> release() async {
    await cancel();
    try {
      await _controller.releaseModel();
    } on Object catch (error) {
      // Releasing a model when nothing is parked is not worth surfacing.
      Log.w('releasing the whisper model threw — $error');
    }
  }
}

/// One [WhisperSpeechRecognizer.transcribeStream] call.
///
/// ⚠️ Per call, not fields on the recogniser. A cancel through the stream's
/// onCancel no longer waits for the session, so an old run can still be
/// finishing when the next one starts. With shared fields it nulled the new
/// session and cancelled the new recording's microphone when it ended.
final class _Run {
  StreamController<Uint8List>? feed;

  /// Completes once the binding has received every chunk of [feed] and its
  /// done event, which is when it is safe to call the session's `stop()`.
  final Completer<void> drained = Completer<void>();

  /// Set when the feed was closed before it existed.
  bool stopRequested = false;

  StreamSubscription<Uint8List>? audio;
  WhisperLiveSession? session;
  bool started = false;
  bool cancelled = false;

  /// Completes when the run has handed the native session back.
  final Completer<void> done = Completer<void>();

  /// Closes the feed, which is what makes the binding finalise. Idempotent
  /// because stop, cancel, end-of-audio and an audio error all lead here.
  void closeFeed() {
    final StreamController<Uint8List>? f = feed;
    if (f == null) {
      stopRequested = true;
      return;
    }
    if (f.isClosed) return;
    // ⚠️ Not awaited: its future completes only once the binding has taken
    // the done event, which is after the model has loaded — and never when
    // the load failed, because a single-subscription controller nobody
    // listened to never completes close(). Awaited, Stop, Cancel and the
    // pipeline's teardown sat through the load, and forever after a failure.
    unawaited(
      f.close().whenComplete(() {
        if (!drained.isCompleted) drained.complete();
      }),
    );
  }
}
