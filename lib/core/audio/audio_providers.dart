import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/audio/audio_recorder.dart';
import 'package:tasuke_ai/core/audio/record_audio_recorder.dart';

/// The single microphone.
///
/// Two public providers expose two *views* of one object — the port and the
/// level stream — and both read this one. Constructing the adapter twice would
/// give the app two `record` instances fighting over one audio session, which
/// on Android surfaces as the second `startStream` throwing and on iOS as the
/// first session going silent.
final Provider<RecordAudioRecorder> recordAudioRecorderProvider =
    Provider<RecordAudioRecorder>((Ref ref) {
      final RecordAudioRecorder recorder = RecordAudioRecorder();
      ref.onDispose(() => unawaited(recorder.dispose()));
      return recorder;
    });

/// The port. Tests override this one with a fake that replays PCM fixtures.
final Provider<AudioRecorder> audioRecorderProvider = Provider<AudioRecorder>(
  (Ref ref) => ref.watch(recordAudioRecorderProvider),
);

/// The waveform's input. Overridden separately so a widget test can drive the
/// level animation without also having to fake audio bytes.
final Provider<AudioLevelSource> audioLevelSourceProvider =
    Provider<AudioLevelSource>(
      (Ref ref) => ref.watch(recordAudioRecorderProvider),
    );
