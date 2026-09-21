#!/usr/bin/env bash
# Downloads the extractor model and prints its SHA-256, so the constant in
# lib/core/models/model_installer.dart can be filled in.
#
#   tool/refresh_model_checksums.sh
#   KEEP=1 tool/refresh_model_checksums.sh       # leave the file on disk
#
# ⚠️ Never guess or hand-edit this digest.
#
# ModelInstaller deletes any download whose SHA-256 does not match the constant.
# A wrong constant therefore does not produce a checksum warning — it produces
# an app that downloads 219 MB, deletes it, and shows modelSetupChecksumFailed,
# forever, on every device, with no way for the user to get past it. That is the
# single worst first-launch failure this app can have.
#
# Re-run this whenever the URL changes. HuggingFace `resolve/main` is a MOVING
# reference: upstream re-quantising the model silently changes the bytes under
# the same URL, and then every install fails at once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/env.sh
. "$SCRIPT_DIR/env.sh"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SPEC="$PROJECT_DIR/lib/core/models/model_installer.dart"

# The URL is read out of the Dart source rather than duplicated here, so the two
# can never disagree. It is a two-line adjacent-string concatenation in
# TasukeModels.extractor; this collects every quoted segment of that expression.
URL="$(sed -n "/url:/,/',\$/p" "$SPEC" | grep -o "'[^']*'" | tr -d "'" | tr -d '\n')"
EXPECTED_SIZE="$(sed -n 's/^[[:space:]]*sizeBytes:[[:space:]]*\([0-9]*\),.*/\1/p' "$SPEC" | head -n 1)"
CURRENT_SHA="$(sed -n "s/^[[:space:]]*sha256:[[:space:]]*'\([^']*\)'.*/\1/p" "$SPEC" | head -n 1)"

if [[ -z "$URL" ]]; then
  echo "refresh_model_checksums: could not read the model URL out of $SPEC" >&2
  exit 1
fi

DEST="${TMPDIR:-/tmp}/$(basename "$URL")"

echo "url:      $URL"
echo "dest:     $DEST"
echo "expected: $EXPECTED_SIZE bytes"
echo "current sha256 constant: ${CURRENT_SHA:-<empty>}"
echo

# -L: HuggingFace redirects resolve/main to a CDN host.
# -C -: resume, so a dropped connection does not restart 219 MB.
echo 'Downloading (this is ~219 MB)…'
curl -L -C - --fail --progress-bar -o "$DEST" "$URL"

ACTUAL_SIZE="$(wc -c <"$DEST" | tr -d ' ')"
SHA="$(sha256sum "$DEST" | cut -d' ' -f1)"

echo
echo "size:   $ACTUAL_SIZE bytes"
echo "sha256: $SHA"
echo

if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
  echo "⚠️  sizeBytes in $SPEC says $EXPECTED_SIZE but the file is $ACTUAL_SIZE."
  echo "    Update sizeBytes too — it drives the free-space check and the"
  echo "    progress bar's denominator."
  echo
fi

if [[ "$SHA" == "$CURRENT_SHA" ]]; then
  echo "✓ The constant already matches. Nothing to do."
else
  cat <<MSG
Paste this into lib/core/models/model_installer.dart, in TasukeModels.extractor:

    sha256: '$SHA',
    sizeBytes: $ACTUAL_SIZE,

(That file belongs to the core module — edit it there, not here.)
MSG
fi

if [[ "${KEEP:-0}" != 1 ]]; then
  rm -f "$DEST"
  echo
  echo "Removed $DEST (set KEEP=1 to keep it)."
fi
