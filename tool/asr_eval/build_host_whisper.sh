#!/usr/bin/env bash
# Builds the app's vendored whisper.cpp (packages/whisper_ggml) as a host
# shared library, libwhisper_ggml.so, so `flutter test` can run the REAL
# WhisperSpeechRecognizer on a Linux (or macOS) desktop without a device.
#
#   tool/asr_eval/build_host_whisper.sh <out-dir> [make -j jobs]
#
# The package's Dart side opens 'libwhisper_ggml.so' by bare name on Linux,
# so point the loader at <out-dir> when running tests:
#
#   LD_LIBRARY_PATH=<out-dir> flutter test <test file>
#
# The source list mirrors packages/whisper_ggml/android/src/whisper/CMakeLists.txt
# (the Android build): every ggml/src and ggml/src/ggml-cpu C/C++ file, the
# ggml-cpu/amx kernels, whisper.cpp/src/whisper.cpp, and main.cpp (the FFI
# surface, compiled with -DDART_SHARED_LIB). CMake globs both arch/arm and
# arch/x86 because the wrong-arch files compile to nothing; here only the
# host's arch directory is compiled, which yields the same objects.
#
# Flags that differ from the Android build, and why:
#   -D_GNU_SOURCE  ggml-cpu.c uses glibc's CPU_ZERO, CPU_ALLOC_SIZE,
#                  pthread_getaffinity_np / pthread_setaffinity_np and getcpu,
#                  which glibc only declares under _GNU_SOURCE (upstream
#                  ggml's CMake adds it on Linux; the NDK does not need it).
#   -march=native  enables the host's AVX2/FMA/F16C paths in the x86 ggml
#                  kernels (upstream's GGML_NATIVE=ON). Without it the build
#                  still links but falls back to baseline SSE2 kernels and
#                  runs several times slower. The resulting .so is tuned to
#                  THIS machine's CPU; rebuild it on any other machine.
# Results can differ from the arm64 device build in the last float bits, so
# transcripts are near-identical to the device, not guaranteed bit-identical.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <out-dir> [jobs]" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$repo_root/packages/whisper_ggml/android/src/whisper"
w="$src/whisper.cpp"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
jobs="${2:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

if [[ ! -f "$w/src/whisper.cpp" ]]; then
  echo "whisper.cpp sources not found under $w" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64 | amd64 | i?86) arch_dir=x86 ;;
  aarch64 | arm64 | arm*) arch_dir=arm ;;
  *) echo "unsupported host arch $(uname -m)" >&2; exit 1 ;;
esac

case "$(uname -s)" in
  Darwin) lib_name=libwhisper_ggml.dylib; shared_flag=-dynamiclib ;;
  *) lib_name=libwhisper_ggml.so; shared_flag=-shared ;;
esac

# Same version defines as the CMakeLists (upstream generates them from git).
defs='-DGGML_USE_CPU -DGGML_VERSION=\"1.9.1\" -DGGML_COMMIT=\"whisper.cpp-v1.9.1\" -DWHISPER_VERSION=\"1.9.1\" -DNDEBUG -D_GNU_SOURCE'
incs="-I$w/include -I$w/ggml/include -I$w/ggml/src -I$w/ggml/src/ggml-cpu -I$w/src"
cflags="-O3 -march=native -fPIC -std=gnu11 $defs $incs"
cxxflags="-O3 -march=native -fPIC -std=c++17 $defs $incs"

shopt -s nullglob
sources=(
  "$w"/ggml/src/*.c
  "$w"/ggml/src/*.cpp
  "$w"/ggml/src/ggml-cpu/*.c
  "$w"/ggml/src/ggml-cpu/*.cpp
  "$w"/ggml/src/ggml-cpu/arch/"$arch_dir"/*.c
  "$w"/ggml/src/ggml-cpu/arch/"$arch_dir"/*.cpp
  "$w"/ggml/src/ggml-cpu/amx/*.cpp
  "$w"/src/whisper.cpp
)
shopt -u nullglob

mkdir -p "$out/obj"
makefile="$out/Makefile"
{
  printf 'OBJS ='
  for i in "${!sources[@]}"; do printf ' obj/%d.o' "$i"; done
  printf ' obj/main.o\n\nall: %s\n\n' "$lib_name"
  for i in "${!sources[@]}"; do
    s="${sources[$i]}"
    if [[ "$s" == *.c ]]; then
      printf 'obj/%d.o: %s\n\tgcc %s -c %s -o $@\n\n' "$i" "$s" "$cflags" "$s"
    else
      printf 'obj/%d.o: %s\n\tg++ %s -c %s -o $@\n\n' "$i" "$s" "$cxxflags" "$s"
    fi
  done
  printf 'obj/main.o: %s/main.cpp %s/main.h\n\tg++ %s -DDART_SHARED_LIB -I%s -c %s/main.cpp -o $@\n\n' \
    "$src" "$src" "$cxxflags" "$src" "$src"
  printf '%s: $(OBJS)\n\tg++ %s -o $@ $(OBJS) -lpthread\n' "$lib_name" "$shared_flag"
} > "$makefile"

echo "building $lib_name from ${#sources[@]} whisper/ggml sources + main.cpp (arch/$arch_dir, -j$jobs)"
make -C "$out" -j"$jobs" > "$out/build.log" 2>&1 || {
  echo "build failed, see $out/build.log" >&2
  tail -n 30 "$out/build.log" >&2
  exit 1
}

# The FFI entry points the Dart side looks up must be exported.
# (nm's output is captured first: `nm | grep -q` under pipefail reports a
# false failure when grep exits early and nm gets SIGPIPE.)
if command -v nm > /dev/null; then
  exported="$(nm -D --defined-only "$out/$lib_name" 2>/dev/null || true)"
  for sym in request stream_start stream_feed stream_append stream_stop stream_abort; do
    grep -qE "[[:space:]]T[[:space:]]_?$sym\$" <<< "$exported" || {
      echo "warning: symbol '$sym' not exported by $out/$lib_name" >&2
    }
  done
fi
echo "built $out/$lib_name"
echo "use: LD_LIBRARY_PATH=$out flutter test <test file>"
