# Tasuke AI

Speak a sentence, get structured tasks. Everything runs on the device.

> *"Tomorrow at 3 PM send the build to James and Friday check App Store"*
> → two tasks, two dates, two reminders.

**No backend. No login. No Firebase. No analytics.** The app makes exactly one
network request in its entire life — downloading its language model on first
launch — and works in airplane mode after that.

- Flutter 3.47.5 / Dart 3.13.4 · iOS 16.4+ · Android (minSdk from the Flutter SDK)
- App id `uz.digitalgroup.tasuke` · version `1.0.0+1` · English only

---

## Getting started

Flutter is not on `PATH` on this machine, and a Gradle build additionally needs
`ANDROID_HOME` and a JDK 17. Source the shared preamble rather than exporting by
hand:

```bash
. tool/env.sh          # source it, do not execute it
flutter pub get
flutter run
```

Every script in `tool/` sources `tool/env.sh` itself, so they can be invoked
directly from anywhere.

---

## The pipeline

```
  mic button
      │
      ▼
  AudioRecorder ──── PCM16 / 16 kHz / mono, streamed, never a file
      │
      ▼
  SpeechRecognizer ── whisper.cpp, on device      (ggml-base.en-q5_1, bundled)
      │  transcript
      ▼
  TaskExtractor ───── llama.cpp + a GBNF grammar  (LFM2-350M-Extract, downloaded)
      │  JSON that is syntactically valid by construction
      ▼
  date parser ─────── deterministic, no model, takes `now` as a parameter
      │
      ▼
  Confirm screen ──── the user sees everything before anything is saved
      │
      ▼
  Drift / SQLite ──── local, then LocalNotifier schedules the reminders
```

Two things in that diagram are deliberate and easy to undo by accident:

- **The grammar, not a prompt.** GBNF constrains the decoder so the model
  *cannot* emit invalid JSON. Replacing it with "please reply in JSON" moves the
  failure from impossible to intermittent.
- **The Confirm screen.** A 350M model is sometimes wrong. Nothing is written
  until the user has looked at it.

---

## Layout and layering

```
lib/
  app/        theme tokens, l10n, router, bootstrap, shared widgets
  core/       ports and platform adapters — clock, time, audio, speech,
              notifications, permissions, purchases, models, database, logging
  features/   one directory per feature, each split domain / data / presentation
packages/
  whisper_ggml/   vendored whisper.cpp binding (upstream hard-depends on an
                  LGPL ffmpeg_kit that was retired in 2025 — see its README)
```

### Rules a guard test enforces

These are not style preferences; each has a test that fails the build.

1. **Nothing under `*/domain/`, `lib/core/time/` or `lib/core/clock/` may import
   `package:flutter`, `package:drift` or `package:flutter_riverpod`.** The
   domain has to be testable in the plain Dart VM, and a single `import
   'package:flutter/material.dart'` for a `Color` is how that stops being true.
2. **`DateTime.now()` is banned outside `lib/core/clock/`.** Take a `Clock`, or
   take `now` as a parameter. This is what makes the date grammar, the quota
   reset and the reminder scheduler testable with a hundred one-line fixtures
   instead of a hundred mocks.
3. **No `print`.** `Log.d/w/e`, and `Log.redact()` for anything derived from a
   transcript or a task title — they are the most sensitive thing the app holds.
4. **Every user-visible string comes from `context.l10n.<key>`** against
   `lib/app/l10n/app_en.arb`.
5. **Design tokens only.** No raw `Color(0x…)`, no `Colors.white`, no magic
   padding outside `lib/app/theme/`.
6. **One importer per plugin.** Exactly one file in the app imports
   `flutter_local_notifications`, one imports `record`, and so on. Everything
   else talks to the port in `lib/core/`, which is what makes widget tests
   possible at all.

### Conventions

- **Riverpod without code generation.** Hand-written `Notifier` /
  `AsyncNotifier` / `StreamProvider` / `Provider`; no `riverpod_annotation`, no
  `@riverpod`. State management adds no build step.
- **No freezed in hand-written code.** Domain entities are plain immutable
  classes with `copyWith`, `==` and `hashCode` — see
  `lib/features/tasks/domain/task.dart` for the shape.
- **Comments explain *why*.** If a comment restates the line below it, delete
  it. A `⚠️` prefix means "this is a trap someone has already fallen into".

Code generation (`drift_dev`, `freezed`, `json_serializable`) is limited to the
database layer and serialisation:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Things that will bite you

Five decisions that look wrong until you know why, each verified against a real
build or a real device rather than reasoned about.

### `compileSdk = 37` is a literal, and it is the only one

Everything else in `android/app/build.gradle.kts` is `flutter.*`, because Play's
target-API floor moves every August and `flutter upgrade` should carry it in for
free. `compileSdk` is pinned because `permission_handler_android`'s AAR metadata
demands API 37 while Flutter 3.47.5 still defaults to 36 — the build fails at the
manifest merger with a message about AAR metadata, not about the plugin. AGP
9.1.0 additionally needs `android.suppressUnsupportedCompileSdk=37` in
`android/gradle.properties`. Drop both the moment Flutter's default reaches 37.

### The release APK is 106 MB because ~95 MB was cut out of it

The first release build was **200.6 MB**. `pubspec.yaml` → `hooks.user_defines.llamadart`
removes two runtimes the app can never reach:

- **LiteRT-LM (~55 MB)** runs `.litertlm` models; Tasuke ships a GGUF.
- **The llama.cpp Vulkan backend (~35 MB)** is GPU offload for a 350M model, on
  a platform whose Vulkan drivers vary wildly by OEM. ggml falls back to CPU
  when the module is absent.

⚠️ `llamadart_native_backends: cpu` as a bare string is **silently ignored** —
the build succeeds and `libggml-vulkan.so` ships anyway. Backends are scoped by
platform; see the `platforms:` map in `pubspec.yaml`. The only way to know it
took is to unzip the APK.

The seven `libggml-cpu-android_armv*.so` variants are deliberately kept: ggml
picks the best at runtime and dropping them slows inference on exactly the newer
phones that make the feature usable.

### The model checksum is measured, never guessed

`TasukeModels.extractor.sha256` is pinned to a real digest.
`ModelInstaller` deletes any download that does not match, so a wrong constant is
not a warning — it is an app that fetches 219 MB, deletes it, and shows the
checksum error forever on every device. HuggingFace `resolve/main` is a moving
reference; re-run `tool/refresh_model_checksums.sh` whenever upstream re-quantises.

### `packages/whisper_ggml` is a fork, and the fork is the point

Upstream hard-depends on `ffmpeg_kit_flutter_new_min` for a converter this app
never calls — it streams 16 kHz mono PCM16 straight from `record`. Keeping it
would cost ~20 MB per ABI, an LGPL-3.0 obligation on a closed-source binary, and
a dependency whose upstream was retired in April 2025. See
`packages/whisper_ggml/NOTICE.md` for exactly what changed and how to re-do it
against a newer upstream.

### Never open a Drift database inside a `testWidgets` body

`testWidgets` runs in `FakeAsync`, where no real timer fires. Drift closes query
streams through a zero-duration timer and its `close()` waits on the real event
loop, so a widget test that constructs a database either reports "a Timer is
still pending" or **deadlocks the isolate outright** — a hang no test timeout can
interrupt, which presents as a native crash. Override `databaseHealthProvider`
and use the in-memory fakes in `test/helpers/fakes.dart`. The database has its
own eighty tests on the Dart VM, where none of that applies.


## Verifying a change

```bash
tool/verify.sh                      # everything that runs on Linux
tool/verify.sh --device             # + the emulator end-to-end test
tool/verify.sh --release            # + the release APK and the 16 KB check
```

Cheapest first: `pub get` → `gen-l10n` → format → analyze → unit/widget tests
with coverage → migration tests → coverage floor → (device) → (release).

### The other scripts

| Script | What it is for |
| ------ | -------------- |
| `tool/env.sh` | The shared environment preamble. Source it; everything else does. |
| `tool/boot_emulator.sh` | Boots `Pixel_7` headless **with `-memory 4096`**. The AVD is configured for 2 GB and the language model does not fit — the app is OOM-killed mid-inference and the symptom is `Lost connection to device` with no Dart exception. |
| `tool/check_16k.sh` | Play requires 16 KB memory-page support for Android 15+ targets. NDK 28.2 links 16 KB-aligned by default, so the risk is entirely **third-party prebuilt `.so` files**. Checks each library's first `LOAD` alignment with `llvm-readelf`, then `zipalign -c -P 16`. |
| `tool/check_coverage.dart` | Coverage floors, overall and per path glob. Written in Dart because `lcov` and `genhtml` are not installed here and are not worth a dependency. |
| `tool/refresh_model_checksums.sh` | Downloads the extractor model, prints its SHA-256, and tells you where to paste it. ⚠️ Never hand-edit that constant: a wrong digest makes the installer delete every successful download, forever, on every device. |

Golden, migration and device tests are tagged (`dart_test.yaml`) and excluded
from the default run.

---

## What a human has to do — Android

1. **Create the upload keystore, once, and never lose it.** Play signs every
   future update against it and there is no self-service recovery.

   ```bash
   keytool -genkey -v -keystore ~/keys/tasuke-upload.jks \
     -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias tasuke
   ```

2. `cp android/key.properties.example android/key.properties` and fill it in.
   The file is gitignored, along with `*.jks` and `*.keystore`.

   ⚠️ Without it the release build **still succeeds**, signed with the debug
   key, and Play rejects the bundle at upload. Gradle prints a warning at
   configure time; that warning is the only signal you get.

3. `flutter build appbundle --release`, then upload.

4. In the Play Console, create the two subscriptions and their base plans
   exactly as `store/PRODUCTS.md` specifies — ids, tags, grace periods. Paste
   `store/REVIEW_NOTES.md` into the testing instructions.

5. Fill in the **Data safety** form: *no data collected, no data shared*. The
   only outbound request is the model download, which carries no personal data.

## What a human has to do — macOS

None of this can be done on this machine; there is no Xcode here and the iOS
side has only been *configured*, never compiled.

1. `cd ios && pod install` — CocoaPods reads `ios/Podfile`, Xcode reads
   `Runner.xcodeproj`. Both are pinned to iOS **16.4** (llamadart's floor) and
   the build only works while they agree.
2. Open `ios/Runner.xcworkspace`, set the team and the signing certificate.
3. Build and run **on a device**, not only the simulator, and tap the
   microphone once. A missing `NSMicrophoneUsageDescription` is a hard crash
   rather than a denial, and nothing on Linux reproduces it.
4. Tap a delivered reminder from the lock screen and confirm it opens the task,
   not Home. That path depends on `AppDelegate.swift` setting the
   `UNUserNotificationCenter` delegate **before** plugin registration.
5. Test purchases against `ios/Runner/Tasuke.storekit` (already wired into the
   Runner scheme), then against a real sandbox account.
6. Confirm `PrivacyInfo.xcprivacy` is in the built `.app`. It is in the Copy
   Bundle Resources phase; a manifest that is only in the repo is an
   **ITMS-91053** rejection minutes after upload, before any human sees the
   build.
7. Archive and upload. `ITSAppUsesNonExemptEncryption` is already `false`, so
   the export-compliance questionnaire will not stop you.

## Store assets

| File | What it is |
| ---- | ---------- |
| `store/PRODUCTS.md` | The two product ids, periods, prices, base-plan tags, grace periods. Kept honest by `test/app/platform/store_products_test.dart`. |
| `store/REVIEW_NOTES.md` | Reviewer instructions, including the exact test script and why guideline 5.1.1(v) is N/A. |
| `store/METRICS.md` | Size, cold start and pipeline latency, per release. |
| `store/store-listing.txt` | Title, subtitle, short and full descriptions, keywords. |
| `store/privacy-policy.html`, `store/terms.html` | Self-contained, ready for GitHub Pages. |
| `assets/legal/privacy_en.md`, `assets/legal/terms_en.md` | The same text, bundled in the app so the legal screens work with no connection. |

⚠️ The Markdown in `assets/legal/` and the HTML in `store/` are the same
document in two formats. Edit both, or they drift — and the version a reviewer
reads on the web stops matching the version in the binary.

Before the first upload, replace the `TODO(human)` support address in
`store/REVIEW_NOTES.md`, `store/store-listing.txt` and both legal documents with
a real, monitored inbox.
# tasuke-ai
