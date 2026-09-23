# whisper_ggml — vendored fork

Upstream: <https://github.com/sk3llo/whisper_ggml> v2.6.0, MIT licensed.
The upstream `LICENSE` file is preserved unchanged in this directory and
continues to govern this code.

This copy embeds whisper.cpp v1.9.1 (MIT, Georgi Gerganov) under
`android/src/whisper/` and `ios/Classes/whisper/`, exactly as upstream ships it.

## What was changed, and why

**Removed the `ffmpeg_kit_flutter_new_min` dependency** and the one file that
used it, `lib/src/whisper_audio_convert.dart`.

Upstream runs every input file through FFmpeg so that any container can be
transcribed. Tasuke AI never needs that: it streams 16 kHz mono PCM16 straight
from `record` into `transcribeLive()`, so no file is produced and the converter
never ran. Keeping the dependency would still have cost:

* **~10–25 MB of native library per ABI** shipped in every build, for code that
  is never executed.
* **An LGPL-3.0 obligation.** FFmpegKit is LGPL-3.0, which on a closed-source
  App Store binary requires dynamic linking plus relink rights for the user.
* **An unmaintained upstream.** Arthenica retired `ffmpeg-kit` in April 2025;
  `ffmpeg_kit_flutter_new` is an unofficial community fork with no successor.

`Whisper.transcribe()` now requires a `.wav` path and throws `ArgumentError`
otherwise, rather than silently handing whisper.cpp a container it cannot read.
`transcribeLive()` — the API Tasuke actually uses — is untouched.

## Other changes

* `ndkVersion` lowered from `29.0.13113456` to `28.2.13676358`, which is what
  Flutter 3.47.5 defaults to. Gradle requires one NDK across the whole build, so
  the higher pin would force every consumer to install a second NDK.
* `x86` dropped from `abiFilters`; Flutter has not supported 32-bit x86 Android
  since 1.22.
* macOS / Windows / Linux platform support removed — Tasuke AI ships iOS and
  Android only, and those trees are several MB of duplicated whisper.cpp source.
* `consumer-rules.pro` no longer keeps FFmpegKit classes (they are gone); it
  keeps only the JNI entry points that `dart:ffi` resolves by name, which R8
  would otherwise rename in release builds.
* `lib/src/whisper_live.dart` hardened against a worker isolate that dies. The
  upstream `startWhisperLiveSession` spawns the isolate with no `onError` and no
  `onExit`, so any failure before the worker sends `'ready'` — a missing
  `libwhisper.so` for one ABI, a `lookupFunction` that finds no symbol, a null
  response pointer — left `await ready.future` waiting for a message that could
  no longer arrive. Nothing upstream of it has a timeout, so Stop became a
  permanent spinner and the recording was lost. Added: VM error/exit ports
  funnelled into one `fail()`, a guard around the `ready.future` await, a
  try/catch around the native load and around every worker message, and a
  nullptr check in `parse()` (`toDartString()` on nullptr segfaults the whole
  process rather than throwing).
* Dev dependencies used only to regenerate freezed/json sources were dropped.
  The generated `.g.dart` / `.freezed.dart` files are committed upstream and are
  preserved here, so this package needs no build step.
* `startWhisperLiveSession` throws on a failed start instead of hanging. An
  `'error'` that arrives before `'ready'` (a failed native load) went to
  `started`, which nobody was awaiting yet, and closed the ports, so
  `await ready.future` never returned; it now goes through `fail()`. The two
  failure paths also no longer `await partials.close()`: nothing ever listened
  to that controller, so its close never completes.
* Cancel without the final pass: `WhisperLiveSession.abort()`, a worker
  `'abort'` arm, and a native `stream_abort()` that hands the context back
  (freed or parked) like `stream_stop()` but runs no inference. Cancelling used
  to sit through a full 30-second-context decode whose text was then dropped.
* Stop no longer starts an extra preview. The buffered tail now rides on the
  `'stop'` message and goes through a native `stream_append()`, which is
  `stream_feed()` without the inference, instead of being sent as a `'feed'`.
  The preview it used to trigger was thrown away by the final pass anyway.
  Both new symbols are looked up in their own `try`, falling back to
  `stream_feed` / `stream_stop`, so a binary built without them behaves as
  before instead of failing every session.
* The energy gate in `stream_feed()` (now `stream_append_locked()`) is
  evaluated per ~100 ms frame instead of once per call. Dart coalesces audio
  while a preview runs, so one call can hold 1-3 s, and a whole-call RMS could
  drop a soft last word or mark seconds of room tone voiced. A call of up to
  150 ms is still one frame, so the per-chunk behaviour the constants were tuned
  on is unchanged.
* `stream_run_inference()` sets `max_tokens` to 10 per second of window + 32.
  With greedy decoding and no temperature fallback, a repetition loop otherwise
  runs all 220 decoder steps and its text is still returned. English-only: a
  multilingual model needs a higher rate.
* Every `stream_*` change above is made identically in
  `android/src/whisper/main.cpp` and `ios/Classes/whisper_flutter_plus.cpp`;
  `test/app/platform/whisper_ffi_parity_test.dart` checks that the streaming
  sections match.
* `ios/whisper_ggml.podspec`: the deprecated `s.xcconfig` is gone, and its
  `CLANG_CXX_LANGUAGE_STANDARD = c++20` moved to `pod_target_xcconfig`.
  CocoaPods also merges `s.xcconfig` into the app target, where its
  `IPHONEOS_DEPLOYMENT_TARGET = 15.6` overrode Runner's 16.4. The pod's own
  deployment target is now 16.4, the app's floor.

## Upgrading

Re-run the vendoring steps against the new upstream archive rather than editing
this tree by hand; the patch points are the ones listed above.
