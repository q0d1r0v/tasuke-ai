# Tasuke AI — release metrics

Measured, not estimated. Re-measure and append a row every release; a size or latency
regression is only visible against the previous number.

## How to reproduce

```sh
. tool/env.sh
flutter build apk --release --split-per-abi
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
tool/check_16k.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
flutter test --coverage && dart run tool/check_coverage.dart --min 85
```

---

## 1.0.0+1 — 2026-09-21

### Artefact size

| Artefact | Size |
|---|---|
| `app-arm64-v8a-release.apk` | **107.5 MB** |
| `app-x86_64-release.apk` | 100.4 MB |
| `app-armeabi-v7a-release.apk` | 83.0 MB |
| `app-release.aab` (all ABIs, what Play receives) | 159.9 MB |

Where the arm64 APK goes:

| Component | Size | Note |
|---|---|---|
| `ggml-base.en-q5_1.bin` | 57.0 MB | the bundled speech model; the app must transcribe offline from first launch |
| native libraries | 45.3 MB | llama.cpp + ggml CPU variants + whisper.cpp + sqlite3 + Flutter |
| Dart, resources, fonts | ~5 MB | Inter is 0.9 MB; the icon fonts tree-shake to under 10 KB |

The vector art (three onboarding illustrations, eight blob frames) is **23 KB of SVG**, and the
`flutter_svg` runtime that draws it costs about **1 MB** of AOT code. The same art as PNG at three
densities would have been roughly 3 MB for a worse result at 2× — a blob frame is nothing but
gradients, which is the one thing SVG stores for free and a bitmap stores worst.

### ⚠️ Size decisions that are load-bearing

> **Superseded since this was measured.** llamadart — and with it llama.cpp, its ggml CPU
> variants and the LiteRT-LM runtime — has been removed from the app, so the
> `hooks.user_defines.llamadart` block below no longer exists. The native-library figure above
> still includes llama.cpp; the next release has to re-measure rather than reuse it.

The first release build was **200.6 MB**. Roughly 95 MB of that was runtime the app can never
reach, and both exclusions live in `pubspec.yaml` under `hooks.user_defines.llamadart`:

* **LiteRT-LM (~55 MB)** — `libLiteRtLm.so` plus five accelerators and a Gemma constraint provider.
  It runs `.litertlm` models only; Tasuke ships a GGUF. Removed with
  `llamadart_native_runtimes: llama_cpp`.
* **The llama.cpp Vulkan backend (~35 MB)** — GPU offload for a 350M model, on a platform whose
  Vulkan drivers vary wildly by OEM. ggml's backend registry falls back to CPU when the module is
  absent, so this costs nothing but the megabytes it saves. Removed with
  `llamadart_native_backends: { platforms: { android: [cpu] } }`.
  ⚠️ A bare `llamadart_native_backends: cpu` is **silently ignored** — the build succeeds and the
  library ships anyway. The only way to know it took is to look inside the APK.

The seven `libggml-cpu-android_armv*.so` variants (~1.5 MB each) are deliberately **kept**: ggml
picks the best one at runtime and dropping them makes inference measurably slower on exactly the
newer phones that make this feature usable.

### 16 KB page support

`tool/check_16k.sh` on the release APKs: **25/25 64-bit libraries at 0x4000 or better, zipalign
verification successful.** Required by Play for apps targeting Android 15+; the risk is always the
third-party prebuilt `.so` files, not our own code.

### Quality gates

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed` | clean, 246 files |
| `flutter analyze` (strict casts/inference/raw-types + 8 house lints) | **No issues found** |
| `flutter test` | **1075 passing**, 0 failing |
| `flutter test --tags golden` | 9 goldens passing (included in the 1075) |
| `dart run tool/check_coverage.dart` | **85.7% overall**; `core/time` 99.1%, `extraction/domain` 93.8%, `tasks/domain` 91.8% |
| `flutter test integration_test -d emulator-5554` | **3 passing on a real Android 15 emulator** |
| architecture guards | 8 passing (domain purity, one importer per plugin, no `DateTime.now()` outside `core/clock`, no `Duration(days:)` rollover, no `print`, no raw colours, no hardcoded prices) |

### On-device verification (Pixel_7 AVD, Android 15, x86_64, 4 GB)

* The real Drift database opens on the device filesystem and answers queries.
* The device timezone resolves (`Asia/Tashkent`) and reminders are computed against it.
* The spec's headline sentence — *"Tomorrow at 3 PM send the build to James and Friday check App
  Store"* — produces **exactly two tasks** with the right dates through the real grammar.
* The save path writes both tasks and assigns stable notification ids.
* All four bottom-nav destinations render without throwing.

Three defects were found **only** by running on the device, and each is now
covered by a test:

1. The Stats week chart overflowed its box by 2 px once the count labels were
   real glyphs — a fixed pixel height inside a fixed box. Now a fraction of the
   remaining space, which cannot overflow whatever the label does.
2. "Next Week" rendered **twice in a row** whenever two tasks fell on different
   days of it: the label describes a range, but grouping was strictly by date.
   Consecutive range-labelled groups are now merged.
3. The bottom nav's `InkWell` filled its whole cell, so the tap highlight was a
   full-bleed rectangle inside a bar with rounded corners and a scooped notch.
   Now a circular `InkResponse`.

A fourth was found by a test rather than by the device, and is worth recording
because nothing else would have caught it: `CaptureController.stop()` settled on
`CapturePhase.idle` for a clip too short to be speech. `captureLocationFor(idle)`
is null, the router's guard turns that into a bounce to Home — so a user who
released Stop half a second early was thrown out of the capture flow with no
message, while the Recording screen's own test for the "say a bit more" copy
kept passing because it was handed that state directly.

### Source

| | |
|---|---|
| `lib/` | 156 files (excluding generated) |
| `test/` + `integration_test/` | 74 files |
| ARB keys | 215 — every user-visible string |

### Not measured here

Cold-start time, pipeline latency and peak RSS need a **physical mid-range Android device**; an
x86_64 emulator on a 16-core workstation tells you nothing useful about either. Measure with:

```sh
flutter run --profile --trace-startup      # build/start_up_info.json
adb shell dumpsys meminfo uz.digitalgroup.tasuke
```

iOS size and startup need a Mac. See `store/REVIEW_NOTES.md` for what else is Mac-only.
