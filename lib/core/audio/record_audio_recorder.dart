import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart' as rec;
import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';

/// Input level, as a stream.
///
/// Deliberately *not* on [AudioRecorder]: the port is the privacy promise —
/// audio in, nothing else — and a waveform is a UI concern that happens to be
/// cheapest to compute where the bytes already are. A fake recogniser in a
/// widget test implements [AudioRecorder] alone and never has to invent levels.
abstract interface class AudioLevelSource {
  /// RMS of each captured chunk, 0..1.
  ///
  /// Raw RMS, not a display value: ordinary speech at arm's length lands
  /// between 0.02 and 0.3, so the waveform applies its own curve. Scaling here
  /// would bake one screen's aesthetic into the audio layer.
  Stream<double> get levels;
}

/// The capture format, stated once.
///
/// ⚠️ 16 kHz / mono / PCM16 **exactly**. This is whisper.cpp's native input
/// format, and the failure mode of getting it wrong is the expensive kind: a
/// 44.1 kHz stereo capture does not throw, it resamples badly inside the
/// binding and silently halves transcription quality. Nobody debugging "the
/// model got worse" looks at the recorder.
const rec.RecordConfig kTasukeRecordConfig = rec.RecordConfig(
  encoder: rec.AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  // echoCancel/noiseSuppress left off on purpose: both lower input gain, and
  // whisper's own energy gate already discards silence. A quiet speaker loses
  // more to the AGC than they gain from the denoiser.
);

/// The one importer of `package:record` in the app.
final class RecordAudioRecorder implements AudioRecorder, AudioLevelSource {
  RecordAudioRecorder({rec.AudioRecorder? recorder})
    : _recorder = recorder ?? rec.AudioRecorder();

  final rec.AudioRecorder _recorder;

  /// Lives for the whole object, not for one session, so the Recording screen
  /// can subscribe before the user taps the mic and keep the same subscription
  /// across a retry.
  final StreamController<double> _levels = StreamController<double>.broadcast();

  StreamController<Uint8List>? _chunks;
  StreamSubscription<Uint8List>? _plugin;
  bool _disposed = false;

  @override
  Stream<double> get levels => _levels.stream;

  /// ⚠️ `request: false`. `record`'s own default is to *prompt* from a method
  /// called `hasPermission`, which would put a system dialog on whatever screen
  /// happens to ask a question. Prompting is [PermissionService]'s job, at a
  /// moment the user can see the reason for.
  @override
  Future<bool> hasPermission() => _recorder.hasPermission(request: false);

  @override
  Future<bool> isRecording() => _recorder.isRecording();

  @override
  Future<Stream<Uint8List>> start() async {
    if (_disposed) {
      throw const RecordingFailure('Recorder disposed');
    }
    if (_chunks != null) {
      throw const RecordingFailure(
        'Already recording',
        kind: RecordingFailureKind.busy,
      );
    }

    final Stream<Uint8List> raw;
    try {
      raw = await _recorder.startStream(kTasukeRecordConfig);
    } on Object catch (error, stack) {
      Log.e('startStream failed', error, stack);
      // A mic held by a phone call or another app surfaces here as a
      // PlatformException; the caller only needs to know which screen to show.
      throw RecordingFailure('Could not start capture', kind: _kindOf(error));
    }

    // Broadcast because two consumers read the same bytes: the recogniser feeds
    // them to whisper, and nothing else may touch the microphone twice — a
    // second `startStream` on one device is a platform error, not a second
    // stream.
    final StreamController<Uint8List> chunks =
        StreamController<Uint8List>.broadcast();
    _chunks = chunks;

    _plugin = raw.listen(
      (Uint8List bytes) {
        if (chunks.isClosed) return;
        chunks.add(bytes);
        if (!_levels.isClosed) _levels.add(rmsOf(bytes));
      },
      onError: (Object error, StackTrace stack) {
        Log.e('capture stream error', error, stack);
        if (!chunks.isClosed) {
          chunks.addError(
            RecordingFailure('Capture failed', kind: _kindOf(error)),
            stack,
          );
        }
        unawaited(_teardown(stopPlatform: true));
      },
      // The platform can end capture on its own — an audio-session interruption
      // does exactly that — so the session has to be able to finish without
      // anyone calling stop().
      onDone: () => unawaited(_teardown(stopPlatform: false)),
    );

    return chunks.stream;
  }

  @override
  Future<void> stop() => _teardown(stopPlatform: true);

  @override
  Future<void> cancel() => _teardown(stopPlatform: true, discard: true);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardown(stopPlatform: true, discard: true);
    await _levels.close();
    await _recorder.dispose();
  }

  /// One cleanup path for stop, cancel, error, platform-done and dispose.
  ///
  /// Four call sites used to mean four half-cleanups, and the leak they left —
  /// a live plugin subscription with no controller to feed — is invisible until
  /// the second recording produces no bytes at all.
  Future<void> _teardown({
    required bool stopPlatform,
    bool discard = false,
  }) async {
    final StreamController<Uint8List>? chunks = _chunks;
    _chunks = null;

    final StreamSubscription<Uint8List>? plugin = _plugin;
    _plugin = null;
    await plugin?.cancel();

    if (stopPlatform) {
      try {
        // `stop()` returns a path for file captures and null for stream ones;
        // there is no file here, which is the whole point of the port.
        if (discard) {
          await _recorder.cancel();
        } else {
          await _recorder.stop();
        }
      } on Object catch (error) {
        // Stopping a recorder that the platform already stopped is not a
        // failure the user can act on.
        Log.w('stopping capture threw — $error');
      }
    }

    if (!_levels.isClosed) _levels.add(0);
    await chunks?.close();
  }

  static RecordingFailureKind _kindOf(Object error) {
    final String text = error.toString().toLowerCase();
    if (text.contains('busy') || text.contains('in use')) {
      return RecordingFailureKind.busy;
    }
    return RecordingFailureKind.unknown;
  }

  /// Root-mean-square of one PCM16 chunk, 0..1.
  ///
  /// ⚠️ Read through [ByteData.sublistView] and `getInt16`, never
  /// `buffer.asInt16List()`: a chunk handed over by the platform can start at
  /// an odd `offsetInBytes`, and `asInt16List` on an odd offset either throws or
  /// — worse — reads every sample one byte out of phase, which looks like
  /// plausible noise rather than like a bug. An odd trailing byte is dropped;
  /// it is half a sample at 16 kHz.
  ///
  /// Public so `test/core/audio/rms_test.dart` can pin it without a microphone.
  static double rmsOf(Uint8List bytes) {
    final int samples = bytes.length ~/ 2;
    if (samples == 0) return 0;
    final ByteData view = ByteData.sublistView(bytes, 0, samples * 2);
    double sumOfSquares = 0;
    for (int i = 0; i < samples; i++) {
      final double sample = view.getInt16(i * 2, Endian.little) / 32768.0;
      sumOfSquares += sample * sample;
    }
    return math.sqrt(sumOfSquares / samples).clamp(0.0, 1.0);
  }
}
