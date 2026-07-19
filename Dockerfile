# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Sandbox image for local coding agents (Claude Code / OpenAI Codex / Copilot).
#
# Build once:   docker build -t agent-sandbox:latest ~/launch-agent
# (agent-sandbox.sh builds it automatically the first time you run it.)
#
# Design goals:
#   - CLIs baked in and version-pinned (no `npm install -g` on every launch,
#     no floating `latest` supply-chain surprises at run time).
#   - Runs as a NON-ROOT user so files created in /workspace aren't root-owned.
# ---------------------------------------------------------------------------

# Pin the base image. Bump this deliberately; don't float on plain `node:20`.
FROM node:20.18.1-bookworm-slim

# Pin agent CLI versions so rebuilds are reproducible. Override at build time:
#   docker build --build-arg CLAUDE_VERSION=2.1.212 -t agent-sandbox:latest .
# Bump these deliberately; check the latest with `npm view <pkg> version`.
ARG CLAUDE_VERSION=2.1.212
ARG CODEX_VERSION=0.144.5

# The GitHub Copilot CLI has changed package names over time. `@github/copilot`
# is the current standalone npm package; if that install fails, fix it here.
ARG COPILOT_PKG=@github/copilot
ARG COPILOT_VERSION=1.0.71

# Minimal OS deps the agents actually use. Installed as root, before we drop.
# tinyproxy is here so the SAME pinned image can double as the egress-filtering
# proxy sidecar in `--net=allowlist` mode (no extra image, no extra supply-chain
# surface). It is never started in normal agent runs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        ripgrep \
        less \
        tinyproxy \
    && rm -rf /var/lib/apt/lists/*

# Install Claude + Codex together (both reliable). Copilot is a separate layer
# so that if its package name is wrong the error clearly points at Copilot and
# doesn't take the other two down with it.
RUN npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

RUN npm install -g "${COPILOT_PKG}@${COPILOT_VERSION}" \
    && npm cache clean --force

# node:20 ships a non-root `node` user (uid 1000). Run as it.
USER node
ENV HOME=/home/node
WORKDIR /workspace

# No magic entrypoint — the launcher passes the agent binary as the command.
ENTRYPOINT []
CMD ["bash"]
