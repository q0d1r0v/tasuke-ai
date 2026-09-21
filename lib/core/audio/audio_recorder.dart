import 'dart:typed_data';

/// Microphone capture.
///
/// The contract is a **stream**, never a file. Tasuke AI's privacy promise is
/// that audio is never written to disk, and the cleanest way to keep a promise
/// like that is to have no API that could break it.
abstract interface class AudioRecorder {
  /// Whether the platform has an input device and the app holds permission.
  Future<bool> hasPermission();

  Future<bool> isRecording();

  /// Starts capture and returns 16 kHz mono little-endian PCM16 chunks.
  ///
  /// Throws [RecordingFailure] if the microphone is unavailable or busy.
  Future<Stream<Uint8List>> start();

  /// Stops capture and closes the stream returned by [start].
  Future<void> stop();

  /// Stops capture and closes the stream without finalising anything.
  Future<void> cancel();

  Future<void> dispose();
}
