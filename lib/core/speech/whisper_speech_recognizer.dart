import 'dart:async';
import 'dart:typed_data';

import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/models/whisper_model_asset.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

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
  }) : _controller = controller ?? WhisperController();

  final WhisperModelAsset _modelAsset;
  final WhisperController _controller;

  /// Injected rather than asked of `record` directly: this file may not import a
  /// second plugin, and "is there a microphone" is a question the recorder and
  /// the permission service already answer between them.
  final Future<bool> Function()? _micAvailable;

  WhisperLiveSession? _session;

  /// The audio actually handed to the binding.
  ///
  /// The caller's stream is **not** passed straight through. Interposing a
  /// controller buys two things that are awkward otherwise: this class learns
  /// when input ended (the binding's `stop()` is the only way to read the final
  /// transcript, and calling it early truncates the recording), and `stop()`
  /// becomes "close the feed" rather than "reach into someone else's stream".
  StreamController<Uint8List>? _feed;
  Completer<void>? _feedClosed;

  StreamSubscription<Uint8List>? _audio;
  bool _cancelled = false;

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
    _cancelled = false;
    out.onListen = () => unawaited(_run(pcm16, out));
    out.onCancel = cancel;
    return out.stream;
  }

  Future<void> _run(
    Stream<Uint8List> pcm16,
    StreamController<SpeechEvent> out,
  ) async {
    StreamSubscription<String>? partials;
    final Completer<void> closed = Completer<void>();
    _feedClosed = closed;
    try {
      final String? modelPath = await _modelAsset.pathIfInstalled();
      if (modelPath == null) {
        throw const TranscriptionFailure(
          'The whisper model is not on disk',
          kind: TranscriptionFailureKind.modelUnavailable,
        );
      }

      final StreamController<Uint8List> feed = StreamController<Uint8List>();
      _feed = feed;

      // `keepModelLoaded: true` parks the model in native memory when the
      // session stops. Loading base.en costs several seconds; a user who
      // records twice in a row would otherwise pay it twice. `release()` gives
      // the memory back.
      final WhisperLiveSession session = await _controller.transcribeLive(
        modelPath: modelPath,
        pcm16Stream: feed.stream,
        keepModelLoaded: true,
      );
      _session = session;

      partials = session.partials.listen(
        (String text) {
          if (!out.isClosed) out.add(SpeechPartial(text));
        },
        // A mid-session native error arrives here and is then followed by
        // whatever text the binding kept, so it is logged rather than
        // forwarded: failing the stream would throw away a usable transcript.
        onError: (Object error, StackTrace stack) =>
            Log.e('whisper partial error', error, stack),
      );

      _audio = pcm16.listen(
        (Uint8List bytes) {
          if (!feed.isClosed) feed.add(bytes);
        },
        onDone: () => unawaited(_closeFeed()),
        onError: (Object error, StackTrace stack) {
          Log.e('audio stream error during transcription', error, stack);
          unawaited(_closeFeed());
        },
      );

      // ⚠️ Wait for the input to end before touching `stop()`. The binding's
      // `stop()` both finalises *and* terminates; calling it while audio is
      // still arriving silently transcribes only the first fraction of a second.
      await closed.future;
      final String text = await session.stop();
      _session = null;

      if (_cancelled) return;
      if (text.trim().isEmpty) {
        throw const TranscriptionFailure(
          'Nothing was said',
          kind: TranscriptionFailureKind.noSpeech,
        );
      }
      if (!out.isClosed) out.add(SpeechFinal(text.trim()));
    } on TranscriptionFailure catch (failure, stack) {
      if (!out.isClosed) out.addError(failure, stack);
    } on Object catch (error, stack) {
      Log.e('transcription failed', error, stack);
      if (!out.isClosed) {
        out.addError(const TranscriptionFailure('Transcription failed'), stack);
      }
    } finally {
      await partials?.cancel();
      await _audio?.cancel();
      _audio = null;
      if (!out.isClosed) await out.close();
    }
  }

  /// Closes the feed, which is what makes the binding finalise. Idempotent
  /// because stop, cancel, end-of-audio and an audio error all lead here.
  Future<void> _closeFeed() async {
    final StreamController<Uint8List>? feed = _feed;
    _feed = null;
    if (feed != null && !feed.isClosed) await feed.close();
    final Completer<void>? closed = _feedClosed;
    if (closed != null && !closed.isCompleted) closed.complete();
  }

  @override
  Future<void> stop() => _closeFeed();

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await _audio?.cancel();
    _audio = null;
    await _closeFeed();
    // Still stopped rather than abandoned: the native context and the worker
    // isolate belong to the session and only `stop()` hands them back. The
    // transcript it returns is dropped because [_cancelled] is set.
    await _session?.stop();
    _session = null;
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
