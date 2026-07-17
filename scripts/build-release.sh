#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-release.sh — produce the single self-contained `agent-sandbox` artifact
# that every install channel (curl / brew / npm) ships.
#
# Takes agent-sandbox.sh (the canonical source) and:
#   1. stamps VERSION="dev"        -> VERSION="<version>"
#   2. replaces the @@EMBEDDED_DOCKERFILE@@ placeholder with the real Dockerfile
#
# Usage:
#   scripts/build-release.sh [VERSION] [OUTDIR]
#
# VERSION defaults to `git describe` (tag minus leading 'v') or "dev".
# OUTDIR  defaults to ./dist. Emits <OUTDIR>/agent-sandbox and .sha256.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/agent-sandbox.sh"
DOCKERFILE="$REPO_ROOT/Dockerfile"

VERSION="${1:-}"
OUTDIR="${2:-$REPO_ROOT/dist}"

if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$REPO_ROOT" describe --tags --always 2>/dev/null || echo dev)"
fi
VERSION="${VERSION#v}"   # strip a leading 'v' from tags like v1.2.3

[ -f "$SRC" ] || { echo "build-release: missing $SRC" >&2; exit 1; }
[ -f "$DOCKERFILE" ] || { echo "build-release: missing $DOCKERFILE" >&2; exit 1; }

PLACEHOLDER="@@EMBEDDED_DOCKERFILE@@"
grep -q "$PLACEHOLDER" "$SRC" || {
  echo "build-release: placeholder $PLACEHOLDER not found in $SRC" >&2
  exit 1
}

mkdir -p "$OUTDIR"
OUT="$OUTDIR/agent-sandbox"

# Build with awk so arbitrary Dockerfile content (backslashes, $, &, etc.) is
# inserted literally — no sed metacharacter surprises. We (1) stamp the version
# on the canonical `VERSION="dev"` line, (2) flip EMBEDDED_DOCKERFILE=0 to 1,
# and (3) replace the lone placeholder line with the Dockerfile verbatim. The
# placeholder match is exact-line so the surrounding comments that mention the
# token by name are never touched.
awk -v version="$VERSION" -v dockerfile="$DOCKERFILE" -v placeholder="$PLACEHOLDER" '
  $0 == "VERSION=\"dev\"" {
    print "VERSION=\"" version "\""
    next
  }
  $0 == "EMBEDDED_DOCKERFILE=0" {
    print "EMBEDDED_DOCKERFILE=1"
    next
  }
  $0 == placeholder {
    while ((getline line < dockerfile) > 0) print line
    close(dockerfile)
    next
  }
  { print }
' "$SRC" > "$OUT"

chmod +x "$OUT"

# Sanity checks: the artifact must be valid bash, must not still contain the
# placeholder, and must report the stamped version.
bash -n "$OUT" || { echo "build-release: generated artifact failed syntax check" >&2; exit 1; }
if grep -q "$PLACEHOLDER" "$OUT"; then
  echo "build-release: placeholder still present after build" >&2
  exit 1
fi

# Checksum (portable across macOS `shasum` and Linux `sha256sum`).
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUTDIR" && sha256sum agent-sandbox > agent-sandbox.sha256 )
else
  ( cd "$OUTDIR" && shasum -a 256 agent-sandbox > agent-sandbox.sha256 )
fi

echo "Built $OUT (version $VERSION)"
echo "Checksum: $(cat "$OUTDIR/agent-sandbox.sha256")"
