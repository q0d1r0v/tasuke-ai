#!/usr/bin/env bash
# Boots the Pixel_7 AVD headless and blocks until Android is actually up.
#
#   tool/boot_emulator.sh            # boots Pixel_7
#   AVD=Pixel_7_API_36 tool/boot_emulator.sh
#
# Idempotent: if a device is already online it returns immediately, so
# verify.sh --device can call it unconditionally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/env.sh
. "$SCRIPT_DIR/env.sh"

AVD="${AVD:-Pixel_7}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"

if adb devices | grep -qE '^emulator-[0-9]+[[:space:]]+device$'; then
  echo "boot_emulator: an emulator is already online — reusing it."
  adb wait-for-device
  exit 0
fi

if ! avdmanager list avd -c 2>/dev/null | grep -qx "$AVD"; then
  echo "boot_emulator: AVD '$AVD' not found. Available:" >&2
  avdmanager list avd -c >&2 || true
  exit 1
fi

# ⚠️ -memory 4096 is not a performance tweak, it is a hard requirement.
#
# The Pixel_7 AVD is configured with 2048 MB. The extractor GGUF is ~219 MB on
# disk but llama.cpp mmaps it and the KV cache plus whisper's ~60 MB model plus
# the Flutter engine do not fit: the kernel OOM-kills the app mid-inference. The
# symptom is `Lost connection to device` with no Dart exception and no crash
# log, which reads like a native segfault in llamadart and is not one.
#
# -no-window/-no-audio: no display or sound device on this machine.
# -gpu swiftshader_indirect: software GL; the host has no usable GPU.
# -no-snapshot-load: a saved snapshot would restore the 2 GB memory setting.
echo "boot_emulator: starting $AVD (headless, 4096 MB)…"
nohup emulator -avd "$AVD" \
  -memory 4096 \
  -no-window \
  -no-audio \
  -no-boot-anim \
  -no-snapshot-load \
  -gpu swiftshader_indirect \
  -accel auto \
  >"${TMPDIR:-/tmp}/emulator-$AVD.log" 2>&1 &

adb start-server >/dev/null 2>&1 || true
adb wait-for-device

echo -n "boot_emulator: waiting for sys.boot_completed"
deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  if (( $(date +%s) > deadline )); then
    echo
    echo "boot_emulator: timed out after ${BOOT_TIMEOUT}s. Log:" >&2
    tail -n 40 "${TMPDIR:-/tmp}/emulator-$AVD.log" >&2 || true
    exit 1
  fi
  echo -n '.'
  sleep 2
done
echo ' up.'

# Animations make every `pumpAndSettle` in the integration test a coin flip.
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

adb devices
