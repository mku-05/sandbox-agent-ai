# launch-agent — sandboxed coding agents

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Docker](https://img.shields.io/badge/Docker-required-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/mku-05/sandbox-agent-ai/pulls)
[![Platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#)

Run Claude Code, OpenAI Codex, or GitHub Copilot CLI inside a locked-down
Docker container so an agent can do **anything inside a chosen folder** and
**nothing else on your filesystem** — regardless of which agent you use.

## What this actually protects (read this first)

A container isolates the **filesystem** and **scopes your credentials**. It does
**not** isolate the **network** — these agents *must* reach Bedrock / OpenAI /
GitHub to work, so outbound network is open by design.

So the honest threat model is:

| Concern | Protected? | Why |
|---|---|---|
| Agent editing/deleting files outside the target folder | ✅ Yes | Only `/workspace` is mounted |
| Agent creating root-owned files on your host | ✅ Yes | Runs as non-root `node` (uid 1000) |
| Privilege escalation inside the container | ✅ Mostly | `--cap-drop=ALL`, `--security-opt=no-new-privileges` |
| Fork bombs / memory blowups | ✅ Bounded | `--pids-limit`, `--memory` |
| Secrets leaking from your shell env | ✅ Yes | Secrets come from a file, never `~/.zshrc` |
| Agent reading/exfiltrating data over the network | ❌ **No** | Network is open; it has to be |
| Agent reading your AWS creds (claude only) | ⚠️ Partial | Mounted read-only; use **short-lived SSO creds** |

If you rely on this to stop an agent from *touching your cloud*, it won't —
scope your credentials (below) instead.

## Files

- `Dockerfile` — the sandbox image: pinned base + pinned agent CLIs, non-root.
- `agent-sandbox.sh` — the launcher (absolute-path fix, per-agent AWS scoping,
  capability drops, persistent per-agent config volume).
- `README.md` — this file.

## One-time setup

### 1. Create the secrets file (outside `~/.zshrc`)

Docker `--env-file` format: `KEY=value`, one per line, **no `export`, no quotes**.

```bash
mkdir -p ~/.secrets
cat > ~/.secrets/agent-sandbox.env <<'EOF'
ATLASSIAN_TOKEN=your_token_value_here
# add other tokens here, one per line
EOF
chmod 600 ~/.secrets/agent-sandbox.env
```

This file is never sourced into your shell and never seen outside the container.
(The launcher creates an empty one automatically if it's missing.)

### 2. Put the launcher on your PATH

```bash
mkdir -p ~/bin
ln -s ~/launch-agent/agent-sandbox.sh ~/bin/agent-sandbox.sh
chmod +x ~/launch-agent/agent-sandbox.sh

# if ~/bin isn't already on PATH:
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 3. Build the image (optional — the launcher does it on first run)

```bash
docker build -t agent-sandbox:latest ~/launch-agent
```

## Day-to-day usage

```bash
agent-sandbox.sh claude  /path/to/project
agent-sandbox.sh codex   /path/to/project
agent-sandbox.sh copilot /path/to/project

# folder defaults to the current directory:
cd /path/to/project && agent-sandbox.sh claude
```

The agent starts with `/workspace` = your project folder and can freely read,
write, and run commands there.

## AWS / Bedrock credentials

Only the `claude` case mounts `~/.aws` (read-only) and sets
`CLAUDE_CODE_USE_BEDROCK=1`. Codex and Copilot never see your AWS creds.

`:ro` prevents *editing* the file, not *reading* it. Because network is open, a
leaked long-lived key could be exfiltrated. **Strongly prefer SSO / short-lived
credentials** so any leak expires quickly:

```bash
aws sso login --profile your-profile
AWS_PROFILE=your-profile agent-sandbox.sh claude /path/to/project
```

`AWS_PROFILE` and `AWS_REGION` are read from your shell (defaults: `default` /
`us-east-1`).

## Git: commit inside, push from the host

`git` is in the image and your project's `.git` is on the bind mount, so
**commits made inside the sandbox land directly in your real repo.** The
launcher wires this up for you:

- **Identity** — your host `git config` name/email are passed in as
  `GIT_AUTHOR_*` / `GIT_COMMITTER_*`, so commits are attributed to you with no
  manual setup. (If you haven't set a global identity on the host, the launcher
  warns and you set it inside the container once — it persists in the config
  volume.)
- **"dubious ownership"** — auto-handled via `safe.directory=*` injected as env
  config, because the host `.git` isn't owned by the container's uid.

**Push is intentionally NOT wired in.** Pushing needs credentials (SSH key /
token), and putting those in the container + open network = exfiltration risk —
the exact "outside" action the sandbox exists to gate. So the workflow is:

```bash
# 1. Agent commits freely inside the sandbox.
# 2. You push from your normal host shell after a glance at the diff:
git -C /path/to/project log --oneline -3
git -C /path/to/project push
```

Commits are already on the host (same `.git`), so this costs nothing extra. If
you later decide you want in-container push, the least-risky route is SSH agent
forwarding (private key stays on the host) — ask and it can be added.

## Hardening applied

The launcher runs every container with:

- `--cap-drop=ALL` — drop all Linux capabilities.
- `--security-opt=no-new-privileges` — block setuid privilege escalation.
- `--pids-limit=512` — cap process count (fork-bomb guard).
- `--memory=4g` — cap memory. Adjust to taste.
- Non-root `node` user (from the Dockerfile).
- Only `/workspace` + a per-agent config volume are writable.

Want more? Add `--read-only` (with `--tmpfs /tmp`) to `COMMON_ARGS` for a
read-only root filesystem.

## Notes & gotchas

- **Relative paths are handled.** The launcher resolves the folder to an
  absolute path before mounting — a bare `./project` won't silently turn into an
  empty named volume the way it does with plain `docker run -v`.
- **Home/root are refused.** `agent-sandbox.sh claude ~` (or `/`) is rejected so
  you can't accidentally hand an agent your entire home directory.
- **Logins persist.** Each agent gets a named volume (`agent-sandbox-<agent>-home`)
  mounted at `/home/node`, so device-login agents (Codex / Copilot) don't
  re-authenticate on every launch. Claude-via-Bedrock authenticates via AWS.
- **Copilot package name.** `@github/copilot` is the current standalone CLI
  package, but GitHub has renamed it before. If the Copilot layer fails to
  build, fix `COPILOT_PKG` in the `Dockerfile`.
- **Version pinning.** The `Dockerfile` pins concrete CLI versions (check newer
  ones with `npm view <pkg> version` and bump the ARGs). Override at build time
  without editing the file, e.g.
  `docker build --build-arg CLAUDE_VERSION=2.1.212 -t agent-sandbox:latest .`.

## Maintenance

```bash
# Rebuild after editing the Dockerfile (e.g. to bump CLI versions):
docker build -t agent-sandbox:latest ~/launch-agent

# Wipe a persisted agent login/config:
docker volume rm agent-sandbox-claude-home   # or -codex-home / -copilot-home
```
