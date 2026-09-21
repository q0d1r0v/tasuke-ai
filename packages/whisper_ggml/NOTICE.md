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
* Dev dependencies used only to regenerate freezed/json sources were dropped.
  The generated `.g.dart` / `.freezed.dart` files are committed upstream and are
  preserved here, so this package needs no build step.

## Upgrading

Re-run the vendoring steps against the new upstream archive rather than editing
this tree by hand; the patch points are the five listed above.
