# launch-agent — sandboxed coding agents

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Docker](https://img.shields.io/badge/Docker-required-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/mku-05/sandbox-agent-ai/pulls)
[![Platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#)

Run Claude Code, OpenAI Codex, or GitHub Copilot CLI inside a locked-down
Docker container so an agent can do **anything inside a chosen folder** and
**nothing else on your filesystem** — regardless of which agent you use.

## What this actually protects (read this first)

A container isolates the **filesystem** and **scopes your credentials**. By
default it does **not** isolate the **network** — these agents *must* reach
Bedrock / OpenAI / GitHub to work, so outbound network is open unless you opt
into `--net=allowlist` (see [Network egress control](#network-egress-control)).

So the honest threat model is:

| Concern | Protected? | Why |
|---|---|---|
| Agent editing/deleting files outside the target folder | ✅ Yes | Only `/workspace` is mounted |
| Agent creating root-owned files on your host | ✅ Yes | Runs as non-root `node` (uid 1000) |
| Privilege escalation inside the container | ✅ Mostly | `--cap-drop=ALL`, `--security-opt=no-new-privileges` |
| Fork bombs / memory blowups | ✅ Bounded | `--pids-limit`, `--memory` |
| Secrets leaking from your shell env | ✅ Yes | Secrets come from a file, never `~/.zshrc` |
| Agent reading/exfiltrating data over the network | ⚠️ Optional | Open by default; **`--net=allowlist`** limits egress to known hosts, `--net=none` blocks it entirely |
| Agent reading your AWS creds (claude only) | ⚠️ Partial | Mounted read-only; use **short-lived SSO creds** |

With the default `--net=open`, if you rely on this to stop an agent from
*touching your cloud*, it won't — either scope your credentials (below) or run
with `--net=allowlist`.

## Install

**The only host dependency is Docker** — the agent CLIs run *inside* the
container, so you don't need Node, Python, or the agents installed on your host.
Pick one channel:

```bash
# Homebrew (macOS / Linux)
brew install mku-05/tap/agent-sandbox

# curl (no package manager, no sudo — installs to ~/.local/bin)
curl -fsSL https://raw.githubusercontent.com/mku-05/sandbox-agent-ai/main/install.sh | bash

# npm (if you already have Node on the host)
npm i -g @mku0502/agent-sandbox
```

Then verify and run:

```bash
agent-sandbox --version
agent-sandbox claude /path/to/project
```

The command is `agent-sandbox`; a back-compat `agent-sandbox.sh` symlink is also
installed. Self-management:

```bash
agent-sandbox --update      # curl installs self-update; brew/npm defer to the package manager
agent-sandbox --uninstall   # removes the binary (+ optionally the Docker image/volumes)
```

The curl installer honors `AGENT_SANDBOX_INSTALL_DIR` (install location) and
`AGENT_SANDBOX_VERSION` (pin a version instead of latest).

## Files

- `Dockerfile` — the sandbox image: pinned base + pinned agent CLIs, non-root.
  This is the canonical source; released builds embed it inline in the launcher.
- `agent-sandbox.sh` — the launcher (absolute-path fix, per-agent AWS scoping,
  capability drops, persistent per-agent config volume).
- `install.sh` — the `curl | bash` installer.
- `scripts/build-release.sh` — stamps the version and embeds the Dockerfile to
  produce the single self-contained `agent-sandbox` artifact all channels ship.
- `Formula/agent-sandbox.rb` — Homebrew formula (source of truth for the tap).
- `npm/` — npm package (`@mku0502/agent-sandbox`) metadata.
- `.github/workflows/release.yml` — on a `v*` tag: build → GitHub Release →
  npm publish → Homebrew tap bump.
- `README.md` — this file.

## Manual setup (from a checkout, no package manager)

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
ln -s ~/launch-agent/agent-sandbox.sh ~/bin/agent-sandbox
chmod +x ~/launch-agent/agent-sandbox.sh

# if ~/bin isn't already on PATH:
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Running from a checkout like this, the launcher reads the sibling `Dockerfile`
and reports its version as `dev`. (The packaged builds embed the Dockerfile and
stamp a real version — see [Releasing](#releasing).)

### 3. Build the image (optional — the launcher does it on first run)

```bash
docker build -t agent-sandbox:latest ~/launch-agent
```

## Day-to-day usage

```bash
agent-sandbox claude  /path/to/project
agent-sandbox codex   /path/to/project
agent-sandbox copilot /path/to/project

# folder defaults to the current directory:
cd /path/to/project && agent-sandbox claude

# restrict what the agent can reach on the network (see below):
agent-sandbox claude /path/to/project --net=allowlist

# print the exact docker command without launching anything:
agent-sandbox claude /path/to/project --dry-run
```

The agent starts with `/workspace` = your project folder and can freely read,
write, and run commands there.

### Agents run with full access inside the sandbox

**The container is the boundary, so the agent doesn't second-guess you.** Each
agent is launched with its own in-app guardrails turned off — no per-command
approval prompts — because the sandbox (filesystem scope, dropped capabilities,
and optional egress allowlist) is what actually confines it. That's the whole
point: let the agent work uninterrupted *because* it can't escape the box.

| Agent | Launched with |
|---|---|
| `claude` | `--dangerously-skip-permissions` |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| `copilot` | `--allow-all-tools` |

> ⚠️ These flags are only appropriate **because** the agent is boxed in. Don't
> copy them into an un-sandboxed agent on your host.

Each is overridable via an environment variable (vendors rename these flags from
time to time). Set it to a different flag, or to empty to fall back to the
agent's default cautious mode:

```bash
# Run Claude in its normal prompt-for-permission mode instead:
AGENT_SANDBOX_CLAUDE_ARGS="" agent-sandbox claude /path/to/project

# Override the flag if a vendor renames it:
AGENT_SANDBOX_CODEX_ARGS="--full-auto" agent-sandbox codex /path/to/project
```

The variables are `AGENT_SANDBOX_CLAUDE_ARGS`, `AGENT_SANDBOX_CODEX_ARGS`, and
`AGENT_SANDBOX_COPILOT_ARGS`. Use `--dry-run` to see exactly what gets passed.

## Network egress control

By default the sandbox scopes your **filesystem and credentials** but leaves
**outbound network open** — the agents need to reach their backends. If your
worry is an agent (or a compromised dependency it pulls in) *exfiltrating* your
code or secrets, restrict egress:

```bash
# Only let the agent reach a known set of hosts (model backends, GitHub, npm):
agent-sandbox claude /path/to/project --net=allowlist

# Allow an extra host on top of the defaults (repeatable):
agent-sandbox claude /path/to/project --net=allowlist --allow=internal.corp.example

# Fully offline — no network at all:
agent-sandbox codex /path/to/project --net=none
```

**How allowlist mode works.** The agent container joins an `--internal` Docker
network with **no route to the internet**. Its only way out is a small
[`tinyproxy`](https://tinyproxy.github.io/) sidecar (built from this same pinned
image — no extra download) that filters HTTPS `CONNECT` by hostname against the
allowlist and denies everything else. It's a *destination* filter: there's no
TLS interception, so the proxy never sees your traffic, only where it's headed.
Ports other than 443 are refused.

The default allowlist covers what a coding agent legitimately needs — Anthropic
/ Bedrock (`anthropic.com`, `amazonaws.com`), OpenAI (`openai.com`), GitHub +
Copilot (`github.com`, `githubusercontent.com`, `githubcopilot.com`, …), and the
npm registry (`npmjs.org`, `npmjs.com`, `nodejs.org`). Extend it without editing
anything via `--allow=<domain>` (repeatable) or the `AGENT_SANDBOX_ALLOW`
environment variable (space- or comma-separated). Matching is by domain suffix,
so `anthropic.com` also permits `api.anthropic.com`.

> If an agent suddenly can't reach a service in allowlist mode, its domain
> almost certainly isn't listed — add it with `--allow=`.

**See exactly what will run, first.** `--dry-run` prints the precise
`docker`/proxy commands (and the resolved allowlist) without launching anything
— it doesn't even require Docker to be installed:

```bash
agent-sandbox claude /path/to/project --net=allowlist --dry-run
```

## AWS / Bedrock credentials

Only the `claude` case mounts `~/.aws` (read-only) and sets
`CLAUDE_CODE_USE_BEDROCK=1`. Codex and Copilot never see your AWS creds.

`:ro` prevents *editing* the file, not *reading* it. Because network is open, a
leaked long-lived key could be exfiltrated. **Strongly prefer SSO / short-lived
credentials** so any leak expires quickly:

```bash
aws sso login --profile your-profile
AWS_PROFILE=your-profile agent-sandbox claude /path/to/project
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
- **Home/root are refused.** `agent-sandbox claude ~` (or `/`) is rejected so
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

## Releasing

Releases are cut by pushing a `v*` tag. The `release` workflow builds the
self-contained artifact, attaches it to a GitHub Release, publishes to npm, and
bumps the Homebrew tap.

**One-time maintainer setup:**

1. **Create the tap repo** `mku-05/homebrew-tap` (public). That name is what
   makes `brew install mku-05/tap/agent-sandbox` resolve.
2. **Add two Actions secrets** to `mku-05/sandbox-agent-ai`
   (Settings → Secrets and variables → Actions):
   - `NPM_TOKEN` — an npm **automation** token with publish rights to the
     `@mku0502` scope.
   - `HOMEBREW_TAP_TOKEN` — a fine-grained PAT with **contents: write** on
     `mku-05/homebrew-tap`.

   The npm and brew jobs skip themselves if their secret is absent, so the first
   release still succeeds (GitHub Release only) before you've set these up.

**Cut a release:**

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Build the artifact locally** (what CI does, for testing):

```bash
scripts/build-release.sh 1.0.0 dist   # -> dist/agent-sandbox + .sha256
```
