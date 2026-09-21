#!/usr/bin/env bash
# Verifies that every native library in a release APK supports 16 KB memory
# pages, and that the APK's zip entries are aligned for them.
#
#   tool/check_16k.sh [path/to/app-release.apk]
#
# ⚠️ Why this exists at all.
#
# Play requires 16 KB page support for apps targeting Android 15+. Devices with
# a 16 KB kernel page size cannot load a shared library whose LOAD segments are
# only 4 KB-aligned: the loader refuses, and the app crashes on startup — on
# those devices only. NDK 28.2 links 16 KB-aligned by DEFAULT, so our own code
# is fine and it is very easy to conclude the whole problem is handled.
#
# It is not. The risk is THIRD-PARTY PREBUILT .so FILES: libsqlite3, the
# whisper.cpp and llama.cpp binaries, and the Play Billing native bits all
# arrive as compiled artifacts built by someone else with someone else's linker
# flags. One 4 KB-aligned library in the bundle and Play rejects the release, or
# worse, accepts it and the crash rate on new hardware climbs quietly.
#
# Two independent checks, because they catch different failures:
#   1. `llvm-readelf -l` on each .so — the LINKER's alignment (0x4000).
#   2. `zipalign -c -P 16` on the APK — the PACKAGER's alignment inside the zip.
# A library can pass one and fail the other.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/env.sh
. "$SCRIPT_DIR/env.sh"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APK="${1:-$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk}"

if [[ ! -f "$APK" ]]; then
  echo "check_16k: no APK at $APK" >&2
  echo "check_16k: build one first:  flutter build apk --release" >&2
  exit 1
fi

# Neither tool is on PATH; both ship inside the SDK. Newest first.
READELF="$(find "$ANDROID_HOME/ndk" -path '*/linux-x86_64/bin/llvm-readelf' 2>/dev/null | sort -V | tail -n 1)"
ZIPALIGN="$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -name zipalign 2>/dev/null | sort -V | tail -n 1)"

if [[ -z "$READELF" ]]; then
  echo "check_16k: llvm-readelf not found under $ANDROID_HOME/ndk" >&2
  exit 1
fi
if [[ -z "$ZIPALIGN" ]]; then
  echo "check_16k: zipalign not found under $ANDROID_HOME/build-tools" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "check_16k: $APK"
echo "check_16k: readelf  $READELF"
echo "check_16k: zipalign $ZIPALIGN"
echo

unzip -q -o "$APK" 'lib/*' -d "$WORK" || true

mapfile -t LIBS < <(find "$WORK/lib" -name '*.so' 2>/dev/null | sort)
if [[ "${#LIBS[@]}" -eq 0 ]]; then
  echo "check_16k: the APK contains no lib/*/*.so — that is not a Flutter release APK." >&2
  exit 1
fi

FAILED=0
printf '%-10s  %-46s  %s\n' 'ALIGN' 'LIBRARY' 'VERDICT'
printf '%s\n' '------------------------------------------------------------------------------'

for lib in "${LIBS[@]}"; do
  rel="${lib#"$WORK"/}"

  # ⚠️ 16 KB pages are a 64-bit requirement. Play's rule covers arm64-v8a and
  # x86_64; 32-bit ABIs run on 4 KB kernels and a 0x1000-aligned armeabi-v7a
  # library is correct, not a defect. Failing the gate on one would either send
  # somebody hunting a non-bug or push them into dropping an ABI that still has
  # users.
  case "$rel" in
    lib/armeabi-v7a/*|lib/x86/*)
      printf '%-10s  %-46s  %s\n' '-' "$rel" 'skipped (32-bit ABI)'
      continue
      ;;
  esac

  # The first LOAD program header carries the segment alignment the loader
  # honours. 0x4000 = 16 KB (good), 0x1000 = 4 KB (rejected on 16 KB devices).
  align="$(
    "$READELF" -l "$lib" 2>/dev/null \
      | awk '$1 == "LOAD" { print $NF; exit }'
  )"

  if [[ -z "$align" ]]; then
    printf '%-10s  %-46s  %s\n' '?' "$rel" 'NO LOAD SEGMENT — not an ELF?'
    FAILED=1
    continue
  fi

  case "$align" in
    0x4000|0x8000|0x10000)
      # ≥16 KB. Larger is legal and still loads on a 16 KB kernel.
      printf '%-10s  %-46s  %s\n' "$align" "$rel" 'ok'
      ;;
    *)
      printf '%-10s  %-46s  %s\n' "$align" "$rel" 'FAIL — needs 0x4000'
      FAILED=1
      ;;
  esac
done

echo
echo 'check_16k: zip entry alignment (zipalign -c -P 16 -v 4)'
# -P 16 tells zipalign to expect 16 KB page alignment for uncompressed .so
# entries; -c is check-only. The per-entry output is thousands of lines, so only
# the failures and the verdict are shown.
set +e
ZOUT="$("$ZIPALIGN" -c -P 16 -v 4 "$APK" 2>&1)"
ZRC=$?
set -e
echo "$ZOUT" | grep -i 'bad\|fail' || true
echo "$ZOUT" | tail -n 1

if [[ "$ZRC" -ne 0 ]]; then
  FAILED=1
fi

echo
if [[ "$FAILED" -ne 0 ]]; then
  echo "✗ check_16k FAILED — this build will be rejected by Play for apps targeting Android 15+." >&2
  echo "  For a bad third-party .so there is no local fix: upgrade the plugin, or ask upstream" >&2
  echo "  to rebuild with '-Wl,-z,max-page-size=16384'." >&2
  exit 1
fi

echo "✓ check_16k: ${#LIBS[@]} libraries are 16 KB-aligned and the APK is aligned for them."
