# Audio fixtures

This directory is **deliberately empty of audio**.

`integration_test/real_pipeline_test.dart` is the only test that runs the real
whisper.cpp binding, and it takes its clip by **path**, from
`--dart-define=TASUKE_AUDIO_FIXTURE=...`, never from the asset bundle:

```bash
curl -L -o /tmp/jfk.wav \
  https://github.com/ggml-org/whisper.cpp/raw/master/samples/jfk.wav
adb shell mkdir -p /data/local/tmp/tasuke
adb push /tmp/jfk.wav /data/local/tmp/tasuke/jfk.wav
adb shell chmod 644 /data/local/tmp/tasuke/jfk.wav

flutter test integration_test/real_pipeline_test.dart \
  --dart-define=TASUKE_AUDIO_FIXTURE=/data/local/tmp/tasuke/jfk.wav \
  -d <device-id>
```

⚠️ **Why not commit the WAV and list it under `flutter.assets`.** Anything in
that list is packaged into the release APK and the IPA. A 352 KB test clip would
ship to every user forever, to be read by nothing. Declaring it "just for
debug" is not possible — Flutter has one asset manifest per package.

The default expectation is the whisper.cpp project's own `samples/jfk.wav`
(public domain, 16 kHz mono PCM16, 11 s). Any other clip works as long as it is
16 kHz mono PCM16 — the test asserts that from the `fmt ` chunk and fails loudly
otherwise, because whisper.cpp accepts nothing else and silently transcribes
noise if you feed it something else.

Override the expected phrase with `--dart-define=TASUKE_AUDIO_EXPECT=...`.

## Measured

Android emulator, x86_64, API 35:

| | Before backpressure | After |
|---|---:|---:|
| Copy the model out of the bundle (59.7 MB) | 1 011 ms | 618 ms |
| Transcribe an 11 s clip | **26 764 ms** | **3 663 ms** |
| Stop → final transcript, 44 s of backlog | (never returned) | **6 171 ms** |

The 7× is not a tuning win, it is the shape of the bug: every 128 ms chunk of
audio used to be its own message in the worker's mailbox, and each one ran
inference over the whole window again. See the note on
`WhisperLiveSession._pending` in the vendored package.

x86_64 under emulation is the slow case: the static whisper build targets
baseline `armv8-a` with no `-march` override (see
`packages/whisper_ggml/android/src/whisper/CMakeLists.txt` — the fp16 flags
SIGILL on armv8.0 hardware), and the emulator has neither NEON nor the host's
AVX path. Re-measure on real arm64 before quoting a number to anyone.
