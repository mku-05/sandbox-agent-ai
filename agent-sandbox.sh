#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# agent-sandbox.sh — run a coding agent in a locked-down Docker sandbox.
#
#   Usage: agent-sandbox.sh [claude|copilot|codex] [/path/to/folder]
#
# What the sandbox gives you:
#   - Full read/write to the ONE target folder (mounted at /workspace) and
#     nothing else on your host filesystem.
#   - A non-root user, dropped Linux capabilities, and pid/memory limits.
#   - Secrets injected from a file that is never sourced into your shell.
#
# What it does NOT give you:
#   - Network isolation. Agents need the internet (Bedrock / OpenAI / GitHub),
#     so outbound network is OPEN. Treat this as filesystem + credential
#     scoping, not network containment.
# ---------------------------------------------------------------------------

set -euo pipefail

IMAGE="agent-sandbox:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENT="${1:?Usage: agent-sandbox.sh [claude|copilot|codex] [/path/to/folder]}"
RAW_FOLDER="${2:-$(pwd)}"

# --- Resolve to an ABSOLUTE path. Docker bind mounts require it; a relative
#     path silently becomes a named volume and the agent sees an empty dir. ---
if [ ! -d "$RAW_FOLDER" ]; then
  echo "Error: '$RAW_FOLDER' is not a directory." >&2
  exit 1
fi
FOLDER="$(cd "$RAW_FOLDER" && pwd)"

# --- Guardrail: refuse to mount your whole home dir or the filesystem root. ---
case "$FOLDER" in
  "$HOME" | "/")
    echo "Refusing to mount '$FOLDER' — pick a project subfolder, not your whole home/root." >&2
    exit 1
    ;;
esac

# --- Secrets file (Docker --env-file format: KEY=value, no 'export', no quotes). ---
SECRETS_FILE="$HOME/.secrets/agent-sandbox.env"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "No secrets file at $SECRETS_FILE — creating an empty one (chmod 600)."
  mkdir -p "$(dirname "$SECRETS_FILE")"
  touch "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
fi

# --- Build the image on first use. ---
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image '$IMAGE' not found — building it (one-time)…"
  docker build -t "$IMAGE" "$SCRIPT_DIR"
fi

# --- Per-agent named volume so login/config survives between runs. ---
CONFIG_VOL="agent-sandbox-${AGENT}-home"

# --- Git: make commits "just work" inside the sandbox, WITHOUT carrying any
#     push credentials in. The agent commits to the bind-mounted .git; you run
#     `git push` from your host shell afterward.
#
#   * Identity: inherit your host git identity via env vars so commits are
#     attributed to you (no manual `git config` inside the container).
#   * safe.directory=*: the host .git is owned by your host uid, not the
#     container's uid 1000, so git would otherwise refuse with "dubious
#     ownership". Injected via git's env-config so no file is touched and it
#     also covers submodule paths. Safe here because the whole mount is trusted.
GIT_ENV_ARGS=(
  -e GIT_CONFIG_COUNT=1
  -e GIT_CONFIG_KEY_0=safe.directory
  -e GIT_CONFIG_VALUE_0=*
)
GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  GIT_ENV_ARGS+=(
    -e GIT_AUTHOR_NAME="$GIT_NAME"
    -e GIT_AUTHOR_EMAIL="$GIT_EMAIL"
    -e GIT_COMMITTER_NAME="$GIT_NAME"
    -e GIT_COMMITTER_EMAIL="$GIT_EMAIL"
  )
else
  echo "Note: host git user.name/user.email not set — set them inside the" >&2
  echo "      container (git config --global …) before committing." >&2
fi

COMMON_ARGS=(
  -it --rm
  --hostname agent-sandbox
  -v "$FOLDER":/workspace
  -v "$CONFIG_VOL":/home/node
  -w /workspace
  --env-file "$SECRETS_FILE"
  "${GIT_ENV_ARGS[@]}"
  # --- Hardening ---
  --cap-drop=ALL
  --security-opt=no-new-privileges
  --pids-limit=512
  --memory=4g
)

case "$AGENT" in
  claude)
    # Bedrock needs AWS creds. Mount them read-only and ONLY for claude.
    # Prefer short-lived SSO creds over long-lived keys in ~/.aws/credentials.
    docker run "${COMMON_ARGS[@]}" \
      -v "$HOME/.aws":/home/node/.aws:ro \
      -e AWS_PROFILE="${AWS_PROFILE:-default}" \
      -e AWS_REGION="${AWS_REGION:-us-east-1}" \
      -e CLAUDE_CODE_USE_BEDROCK=1 \
      "$IMAGE" claude
    ;;
  copilot)
    docker run "${COMMON_ARGS[@]}" "$IMAGE" copilot
    ;;
  codex)
    docker run "${COMMON_ARGS[@]}" "$IMAGE" codex
    ;;
  *)
    echo "Unknown agent: '$AGENT' (use claude, copilot, or codex)" >&2
    exit 1
    ;;
esac
