#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — one-line installer for agent-sandbox.
#
#   curl -fsSL https://raw.githubusercontent.com/mku-05/sandbox-agent-ai/main/install.sh | bash
#
# Downloads the released `agent-sandbox` artifact, verifies its sha256, and
# installs it (no sudo) into ~/.local/bin by default.
#
# Environment overrides:
#   AGENT_SANDBOX_INSTALL_DIR   where to install       (default: ~/.local/bin)
#   AGENT_SANDBOX_VERSION       pin a version, e.g. 1.2.3 (default: latest)
# ---------------------------------------------------------------------------

set -euo pipefail

REPO="mku-05/sandbox-agent-ai"
BIN_NAME="agent-sandbox"
INSTALL_DIR="${AGENT_SANDBOX_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${AGENT_SANDBOX_VERSION:-latest}"

err()  { echo "install: $*" >&2; }
die()  { err "$*"; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required."

# --- Resolve download URLs. `latest` uses GitHub's redirect; a pinned version
#     targets the tag directly. ---
if [ "$VERSION" = "latest" ]; then
  BASE="https://github.com/$REPO/releases/latest/download"
else
  BASE="https://github.com/$REPO/releases/download/v${VERSION#v}"
fi
ART_URL="$BASE/$BIN_NAME"
SUM_URL="$BASE/$BIN_NAME.sha256"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $BIN_NAME ($VERSION)…"
curl -fSL --proto '=https' --tlsv1.2 -o "$TMP/$BIN_NAME" "$ART_URL" \
  || die "download failed ($ART_URL). Is there a published release yet?"

# --- Verify checksum when the release publishes one (it does). Compare only
#     the hash field so a differing filename/path in the file doesn't matter. ---
if curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/$BIN_NAME.sha256" "$SUM_URL" 2>/dev/null; then
  expected="$(awk '{print $1}' "$TMP/$BIN_NAME.sha256")"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$TMP/$BIN_NAME" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$TMP/$BIN_NAME" | awk '{print $1}')"
  else
    actual=""
    err "no sha256 tool found — skipping checksum verification."
  fi
  if [ -n "$actual" ]; then
    [ "$expected" = "$actual" ] || die "checksum mismatch (expected $expected, got $actual)."
    echo "Checksum verified."
  fi
else
  err "no checksum published — skipping verification."
fi

chmod +x "$TMP/$BIN_NAME"
mkdir -p "$INSTALL_DIR"
mv -f "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"

# --- Back-compat symlink for anyone who still types the old `.sh` name. ---
ln -sf "$INSTALL_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME.sh"

echo "Installed to $INSTALL_DIR/$BIN_NAME"

# --- PATH hint if the install dir isn't already reachable. ---
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo
    echo "⚠  $INSTALL_DIR is not on your PATH. Add it:"
    echo "     echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

# --- Docker is the one hard host dependency. ---
if ! command -v docker >/dev/null 2>&1; then
  echo
  echo "⚠  Docker was not found. agent-sandbox needs it to run:"
  echo "     https://www.docker.com/"
fi

echo
echo "Done. Try:  $BIN_NAME --version"
