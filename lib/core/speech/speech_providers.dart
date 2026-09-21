import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/speech/speech_recognizer.dart';
import 'package:tasuke_ai/core/speech/whisper_speech_recognizer.dart';

/// The speech-to-text port.
///
/// Overridden in tests with a fake that replays a scripted [SpeechEvent] stream,
/// which is the only way the capture pipeline is exercisable on a machine with
/// no microphone and no native whisper library.
final Provider<SpeechRecognizer>
speechRecognizerProvider = Provider<SpeechRecognizer>((Ref ref) {
  final WhisperSpeechRecognizer recognizer = WhisperSpeechRecognizer(
    modelAsset: ref.watch(whisperModelAssetProvider),
    // Asked of the recorder rather than of a second plugin: the recogniser file
    // is the single importer of whisper_ggml and nothing else.
    micAvailable: () => ref.read(audioRecorderProvider).hasPermission(),
  );
  // Frees the ggml model from native memory. Without this the ~150 MB stays
  // resident for the life of the process, because `keepModelLoaded: true` is
  // what makes the second recording start instantly.
  ref.onDispose(() => unawaited(recognizer.release()));
  return recognizer;
});

/// Whether transcription can run at all right now. Re-read rather than cached:
/// the answer changes when the asset copy finishes and when the microphone
/// permission changes.
final FutureProvider<SpeechAvailability> speechAvailabilityProvider =
    FutureProvider<SpeechAvailability>(
      (Ref ref) => ref.watch(speechRecognizerProvider).availability(),
    );
