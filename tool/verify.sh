#!/usr/bin/env bash
# The one command that says whether this checkout is shippable.
#
#   tool/verify.sh                 # everything that runs on a Linux box
#   tool/verify.sh --device        # + the emulator end-to-end test
#   tool/verify.sh --release       # + the release build and the 16 KB check
#   tool/verify.sh --device --release
#
# Ordered cheapest-first on purpose: a missing trailing comma should fail in
# four seconds, not after the 40-minute release build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=tool/env.sh
. "$SCRIPT_DIR/env.sh"
cd "$PROJECT_DIR"

WITH_DEVICE=0
WITH_RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --device) WITH_DEVICE=1 ;;
    --release) WITH_RELEASE=1 ;;
    -h|--help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "verify: unknown flag '$arg' (expected --device and/or --release)" >&2
      exit 2
      ;;
  esac
done

STEP=0
step() {
  STEP=$((STEP + 1))
  printf '\n\033[1;34m━━ %d. %s\033[0m\n' "$STEP" "$1"
}

trap 'printf "\n\033[1;31m✗ verify FAILED at step %d\033[0m\n" "$STEP"' ERR

step 'Dependencies'
flutter pub get

step 'Localizations'
# Regenerated rather than assumed: app_localizations.dart is gitignored-adjacent
# generated output, and a stale copy turns a missing ARB key into a green build
# that throws NoSuchMethodError on the device.
flutter gen-l10n

step 'Format'
# --set-exit-if-changed, never a silent rewrite. A formatter that fixes the tree
# as a side effect of verifying it makes `verify` unusable in CI and produces
# diffs nobody asked for.
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool

step 'Analyze'
# Zero issues, not "no errors": the house lint set is the spec.
flutter analyze --fatal-infos --fatal-warnings

step 'Unit and widget tests (with coverage)'
# Excludes four tag families, each for its own reason:
#   golden    — the default comparator is an exact pixel match and this
#               rasteriser does not reproduce BoxShadow byte-for-byte.
#   migration — slow (each case opens an old schema and migrates forward); run
#               as its own step below so a timeout there is unambiguous.
#   device    — needs a real engine, not the Dart VM.
#   asr       — the voice evaluation; needs a host-built whisper library and a
#               manifest of audio clips (test/asr/asr_eval_test.dart).
flutter test --exclude-tags 'golden || migration || device || asr' --coverage

step 'Database migration tests'
flutter test --tags migration

step 'Coverage floor'
# ⚠️ Dart, not lcov/genhtml — neither is installed on this machine and neither
# is a dependency worth adding. See tool/check_coverage.dart.
dart run tool/check_coverage.dart \
  --min 80 \
  --min-path 'lib/core/time/**=95' \
  --min-path 'lib/features/extraction/domain/**=93' \
  --min-path 'lib/features/tasks/domain/**=90'

if [[ "$WITH_DEVICE" == 1 ]]; then
  step 'Emulator end-to-end'
  "$SCRIPT_DIR/boot_emulator.sh"
  # integration_test drives the real pipeline: whisper.cpp → rule-based
  # extractor → Drift → notification. It is the only test that proves the
  # native libraries actually load.
  flutter test integration_test --device-id emulator-5554
fi

if [[ "$WITH_RELEASE" == 1 ]]; then
  # ⚠️ The Android plugin registrant is generated per build type and goes
  # STALE across them: after an integration-test run it still registers
  # `integration_test`, a dev dependency, and the release build then fails to
  # compile with "package dev.flutter.plugins.integration_test does not exist".
  rm -rf "$PROJECT_DIR/android/app/src/main/java/io/flutter/plugins"

  step 'Release APK'
  # An APK, not an AAB: check_16k.sh needs to unzip real lib/<abi>/*.so, and an
  # app bundle does not contain them in a readable layout.
  flutter build apk --release

  step '16 KB page alignment'
  "$SCRIPT_DIR/check_16k.sh" build/app/outputs/flutter-apk/app-release.apk
fi

trap - ERR
printf '\n\033[1;32m✓ verify passed (%d steps)\033[0m\n' "$STEP"
