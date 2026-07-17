#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# agent-sandbox — run a coding agent in a locked-down Docker sandbox.
#
#   Usage: agent-sandbox [claude|copilot|codex] [/path/to/folder]
#          agent-sandbox --version | --update | --uninstall | --help
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
#
# Packaging note: released builds embed the Dockerfile inline (see the
# emit_dockerfile placeholder below) so the tool is a single self-contained
# file. In a dev checkout the placeholder is untouched and we fall back to the
# sibling Dockerfile — so running straight from the repo just works.
# ---------------------------------------------------------------------------

set -euo pipefail

# Stamped at release-build time by scripts/build-release.sh. "dev" in a checkout.
VERSION="dev"

IMAGE="agent-sandbox:latest"
INSTALL_URL="https://raw.githubusercontent.com/mku-05/sandbox-agent-ai/main/install.sh"
NPM_PKG="@mku0502/agent-sandbox"

# --- Resolve this script's real path (following symlinks) so the dev-mode
#     Dockerfile fallback can find its sibling Dockerfile and --uninstall can
#     find the actual installed file rather than a symlink to it. ---
resolve_self() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  printf '%s\n' "$src"
}
SELF_PATH="$(resolve_self)"
SCRIPT_DIR="$(cd -P "$(dirname "$SELF_PATH")" >/dev/null 2>&1 && pwd)"

# Flipped to 1 by scripts/build-release.sh once the Dockerfile is embedded
# below. Stays 0 in a dev checkout, which triggers the sibling-Dockerfile path.
EMBEDDED_DOCKERFILE=0

# --- The Dockerfile. Released builds replace the placeholder line below with
#     the real Dockerfile contents and flip EMBEDDED_DOCKERFILE to 1; a dev
#     checkout leaves both untouched and reads the sibling Dockerfile instead.
#     Emitted on stdout, piped to `docker build -` (no COPY/ADD in it, so no
#     build context is needed). ---
emit_dockerfile() {
  if [ "$EMBEDDED_DOCKERFILE" = "1" ]; then
    cat <<'__AGENT_SANDBOX_DOCKERFILE__'
@@EMBEDDED_DOCKERFILE@@
__AGENT_SANDBOX_DOCKERFILE__
    return 0
  fi
  # Dev checkout: fall back to the sibling Dockerfile.
  if [ -f "$SCRIPT_DIR/Dockerfile" ]; then
    cat "$SCRIPT_DIR/Dockerfile"
    return 0
  fi
  echo "agent-sandbox: no embedded Dockerfile and no $SCRIPT_DIR/Dockerfile to fall back to." >&2
  return 1
}

build_image() {
  local df
  df="$(emit_dockerfile)" || return 1
  echo "Image '$IMAGE' not found — building it (one-time)…"
  printf '%s\n' "$df" | docker build -t "$IMAGE" -
}

usage() {
  cat <<EOF
agent-sandbox $VERSION — run a coding agent in a locked-down Docker sandbox.

Usage:
  agent-sandbox <claude|codex|copilot> [/path/to/folder]
  agent-sandbox --version
  agent-sandbox --update
  agent-sandbox --uninstall
  agent-sandbox --help

The folder defaults to the current directory. The agent gets full read/write
to that one folder (mounted at /workspace) and nothing else on your host.
EOF
}

# --- Figure out how this copy was installed, so --update / --uninstall can
#     defer to the right package manager instead of clobbering its files. ---
detect_install_method() {
  case "$SELF_PATH" in
    */node_modules/*|*/lib/node_modules/*) echo npm; return ;;
  esac
  if command -v brew >/dev/null 2>&1; then
    local prefix; prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$prefix" ] && [ "${SELF_PATH#"$prefix"/}" != "$SELF_PATH" ]; then
      echo brew; return
    fi
  fi
  case "$SELF_PATH" in
    */Cellar/*) echo brew; return ;;
  esac
  echo curl
}

cmd_update() {
  case "$(detect_install_method)" in
    brew) echo "Installed via Homebrew — update with:  brew update && brew upgrade agent-sandbox"; return 0 ;;
    npm)  echo "Installed via npm — update with:  npm i -g ${NPM_PKG}@latest"; return 0 ;;
    curl)
      command -v curl >/dev/null 2>&1 || { echo "curl not found; cannot self-update." >&2; return 1; }
      echo "Updating agent-sandbox from $INSTALL_URL …"
      curl -fsSL "$INSTALL_URL" | AGENT_SANDBOX_INSTALL_DIR="$(dirname "$SELF_PATH")" bash
      ;;
  esac
}

cmd_uninstall() {
  case "$(detect_install_method)" in
    brew) echo "Installed via Homebrew — remove with:  brew uninstall agent-sandbox"; return 0 ;;
    npm)  echo "Installed via npm — remove with:  npm rm -g ${NPM_PKG}"; return 0 ;;
  esac
  local dir; dir="$(dirname "$SELF_PATH")"
  echo "Removing $SELF_PATH"
  rm -f "$SELF_PATH"
  if [ -L "$dir/agent-sandbox.sh" ]; then
    rm -f "$dir/agent-sandbox.sh"
    echo "Removed back-compat symlink $dir/agent-sandbox.sh"
  fi
  if command -v docker >/dev/null 2>&1 && [ -t 0 ]; then
    printf 'Also remove the Docker image (%s) and login volumes? [y/N] ' "$IMAGE"
    read -r ans
    case "$ans" in
      y|Y|yes|YES)
        docker image rm "$IMAGE" >/dev/null 2>&1 && echo "Removed image $IMAGE" || true
        for a in claude codex copilot; do
          docker volume rm "agent-sandbox-${a}-home" >/dev/null 2>&1 \
            && echo "Removed volume agent-sandbox-${a}-home" || true
        done
        ;;
      *) echo "Left the Docker image and volumes in place." ;;
    esac
  fi
  echo "Uninstalled agent-sandbox."
}

# --- Top-level dispatch: intercept flags before $1 is treated as an agent. ---
case "${1:-}" in
  -h|--help|help)      usage; exit 0 ;;
  -V|--version|version) echo "agent-sandbox $VERSION"; exit 0 ;;
  --update)            cmd_update; exit $? ;;
  --uninstall)         cmd_uninstall; exit $? ;;
  "")                  usage >&2; exit 1 ;;
esac

AGENT="$1"
RAW_FOLDER="${2:-$(pwd)}"

# --- Docker is required for everything past this point. ---
if ! command -v docker >/dev/null 2>&1; then
  echo "agent-sandbox: Docker is required but was not found on PATH." >&2
  echo "               Install Docker Desktop or engine: https://www.docker.com/" >&2
  exit 1
fi

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
  build_image
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
