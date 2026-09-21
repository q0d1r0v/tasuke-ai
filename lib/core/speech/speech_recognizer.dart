import 'dart:typed_data';

/// What the recogniser emits while it listens.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// A running transcript. Whisper revises earlier words as more audio arrives,
/// so each partial replaces the last rather than appending to it.
final class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);

  final String text;
}

/// The finished transcript. Emitted once, last.
final class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);

  final String text;
}

/// Input level, 0..1, for the waveform. Emitted far more often than the
/// transcript, which is why the Recording screen drives the waveform from a
/// `ValueListenable` rather than from a provider rebuild.
final class SpeechAmplitude extends SpeechEvent {
  const SpeechAmplitude(this.level);

  final double level;
}

/// Transcription failed part-way through.
///
/// The pipeline keeps whatever partial text it already has rather than
/// discarding it: heard words the user has to say again are worse than a
/// slightly short transcript.
final class SpeechError extends SpeechEvent {
  const SpeechError(this.message);

  final String message;
}

/// Whether transcription can run at all right now.
enum SpeechAvailability {
  ready,

  /// The ggml model file is missing or failed its checksum.
  modelUnavailable,

  /// The platform has no microphone, or the app has no permission.
  microphoneUnavailable,
}

/// On-device speech-to-text.
///
/// Implemented by the vendored whisper.cpp binding. The port exists so that a
/// widget test never touches an FFI call: a fake returns a scripted event
/// stream, which is what makes the whole capture pipeline testable on a Linux
/// CI box with no microphone.
abstract interface class SpeechRecognizer {
  Future<SpeechAvailability> availability();

  /// Consumes 16 kHz mono little-endian PCM16 and emits partials, then one
  /// [SpeechFinal] when [pcm16] closes or [stop] is called.
  Stream<SpeechEvent> transcribeStream(Stream<Uint8List> pcm16);

  /// Finalise what has been heard so far.
  Future<void> stop();

  /// Discard the session. No [SpeechFinal] is emitted.
  Future<void> cancel();

  /// Free the model from native memory.
  Future<void> release();
}
