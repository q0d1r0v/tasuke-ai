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

// ⚠️ There was a `speechAvailabilityProvider` here, and nothing ever watched
// it. It has been deleted rather than wired up: availability is a question with
// an answer that expires (the microphone permission can change while the app is
// backgrounded), so the one place that needs it — `VoiceCapturePipeline
// .startRecording` — asks the recogniser directly, at the moment it matters. A
// cached AsyncValue of it could only ever be stale.
//
// `test/arch/provider_reachability_test.dart` now fails the build on any
// provider that nothing consumes, which is what would have caught it.
