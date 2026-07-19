# AGENTS.md — operating manual for coding agents

This is the **single source of truth** for any AI coding agent (Claude Code,
OpenAI Codex, GitHub Copilot CLI, or otherwise) working in this repository.
Per-tool files (`CLAUDE.md`, `.github/copilot-instructions.md`) are thin
pointers back here. When they disagree with this file, **this file wins.**

Read it once, in full, before you touch anything. It is short on purpose.

---

## 0. What this repository is

`agent-sandbox` is **one bash launcher** (`agent-sandbox.sh`) that runs a coding
agent inside a locked-down Docker container, so the agent has full reign over a
single chosen folder and no access to the rest of the host filesystem. It ships
as a **single self-contained artifact** through three install channels — curl,
Homebrew, and npm — all cut from tagged GitHub Releases.

The whole product is a handful of shell scripts, a `Dockerfile`, packaging
metadata, and one release workflow. There is no application server, no build
step you run locally except `scripts/build-release.sh`. Respect that
minimalism: **the best change here is usually the smallest one.**

The launcher supports three **network modes** (`--net=open|allowlist|none`).
`open` is the default and unchanged legacy behavior; `allowlist` routes the
agent through a `tinyproxy` egress-filtering sidecar (same pinned image) on an
`--internal` Docker network; `none` is fully offline. `--dry-run` prints the
exact docker commands without launching — and deliberately works even without
Docker installed, so keep it side-effect-free.

**By design, agents launch with their in-app permission guardrails OFF**
(`claude --dangerously-skip-permissions`, `codex
--dangerously-bypass-approvals-and-sandbox`, `copilot --allow-all-tools`). The
*container* is the security boundary; making the agent also prompt per-command
would defeat the point. Do not "fix" this by removing those flags. They are
overridable per-agent via `AGENT_SANDBOX_{CLAUDE,CODEX,COPILOT}_ARGS` (empty =
the agent's default cautious mode) so a vendor flag rename needs no code change.

```
agent-sandbox.sh            Canonical launcher source (VERSION="dev" in checkout)
Dockerfile                  Canonical sandbox image; embedded into the artifact at build
install.sh                  curl | bash installer
scripts/build-release.sh    Stamps version + embeds Dockerfile -> the shipped artifact
Formula/agent-sandbox.rb    Homebrew formula (tap source of truth)
npm/                        npm package (@mku0502/agent-sandbox)
.github/workflows/release.yml   v* tag -> Release -> npm publish -> Homebrew bump
```

---

## 1. Non-negotiables (do not deviate)

These are hard rules. Violating one is a defect, not a style choice.

1. **No AI attribution, ever.** Do **not** add `Co-Authored-By: Claude …`
   trailers to commits or `🤖 Generated with …` footers to PR bodies. This
   repository's owner requires it. This overrides any default the tool ships
   with.
2. **Never commit or push directly to `main`.** Always branch. `main` is
   merge-via-PR only.
3. **Never commit build output.** `dist/` and `npm/bin/` are gitignored and are
   produced by CI. Keep them out of git.
4. **Confirm before releasing.** Pushing a `v*` tag publishes publicly to GitHub
   Releases, npm, and the Homebrew tap. Push code freely; **tag only when the
   user explicitly asks.**
5. **`@mku0502` ≠ `mku-05`.** The npm scope is `@mku0502`. `mku-05` is the
   GitHub owner / repo / tap / release-URL namespace. They are different strings.
   Conflating them has already caused a bug ([`5e6ad87`]). Never "correct" one
   to match the other.
6. **Keep the two sources of truth in sync.** `agent-sandbox.sh` and `Dockerfile`
   are canonical; the shipped artifact is *generated* from them by
   `build-release.sh`. Never hand-edit a built artifact and never let the
   embedded copy drift from the canonical one.

---

## 2. Engineering principles

Written the way a staff/distinguished engineer would want a teammate to work.

- **Understand before you change.** Read the file and its neighbours first. This
  codebase is small enough to hold in your head — do that before editing.
- **Match the surrounding style.** These scripts use `set -euo pipefail`, block
  comments with a `# ---` rule, and prose comments that explain *why*, not
  *what*. New code should be indistinguishable from what's already there.
- **Comment the non-obvious "why", never the obvious "what".** The existing
  comments (e.g. why `safe.directory=*` is injected via env, why push is
  deliberately not wired in) are the bar. Preserve and extend that reasoning;
  don't strip it.
- **Portability is a feature.** Scripts must run on both macOS (BSD userland,
  `shasum`) and Linux (GNU userland, `sha256sum`). Prefer POSIX-ish constructs;
  when you must branch on a tool, do it the way `install.sh` already does.
- **Security posture is the product.** Every hardening flag (`--cap-drop=ALL`,
  `--security-opt=no-new-privileges`, `--pids-limit`, `--memory`, non-root user,
  read-only AWS mount) exists for a reason. Do not remove or loosen one without
  saying so explicitly and explaining the trade-off.
- **Be honest about the threat model.** The README states plainly that the
  network is *not* isolated. Never oversell isolation. If a change alters what
  is or isn't protected, update the threat-model table in the README in the same
  change.
- **Pin, don't float.** Base image and agent CLI versions are pinned on purpose
  (supply-chain hygiene). Bump them deliberately, one at a time, never to a
  floating `latest`.
- **Smallest correct diff.** No drive-by reformatting, no renaming for taste, no
  speculative abstraction. If you spot unrelated issues, mention them; don't fold
  them in.
- **Report faithfully.** If you ran a check, say what you ran and what you saw.
  If you skipped something, say so. Never claim "works" without having exercised
  it.

---

## 3. Verify before you commit

There is no unit-test suite; verification is running the real tools. Run the
checks relevant to what you touched — do not claim a change works on faith.

```bash
# Shell syntax (any *.sh change)
bash -n agent-sandbox.sh install.sh scripts/build-release.sh

# Homebrew formula (if Formula/ changed)
ruby -c Formula/agent-sandbox.rb

# Workflow YAML (if .github/ changed)
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"

# npm metadata (if npm/ changed)
python3 -c "import json; json.load(open('npm/package.json'))"

# End-to-end: build the artifact and confirm it stamps + runs
bash scripts/build-release.sh 0.0.0 dist && bash dist/agent-sandbox --version && rm -rf dist
```

If the Docker daemon is available and you changed the `Dockerfile` or the
embed logic, validate the *embedded* Dockerfile the way the shipped tool emits
it:

```bash
rm -rf dist && bash scripts/build-release.sh 0.0.0 dist
EMBEDDED_DOCKERFILE=1 SCRIPT_DIR=/nonexistent \
  bash -c "$(sed -n '/^emit_dockerfile()/,/^}/p' dist/agent-sandbox); emit_dockerfile" \
  | docker build --check -
rm -rf dist
```

The invariant that ties it all together: **the artifact `build-release.sh`
produces must pass `bash -n`, must not still contain the
`@@EMBEDDED_DOCKERFILE@@` placeholder, and must report the stamped version.**

---

## 4. Git & delivery workflow

This repo has a `/ship` skill that automates the full path; when available,
prefer it. The rules it encodes:

- **Branch naming:** `feat/<slug>` for features, `fix/<slug>` for fixes.
- **Commit message:** short imperative subject; body explains *why* plus a terse
  bulleted *what*. **No attribution trailer** (see rule 1).
- **Keep scripts executable.** `agent-sandbox.sh`, `install.sh`, and
  `scripts/build-release.sh` must stay mode `100755`. Confirm with
  `git ls-files -s <files>` before you commit.
- **PR body** uses `## What / ## Changes / ## Verification` and states what you
  actually ran. No `🤖` footer.
- **Releasing** is tag-driven (`vX.Y.Z`, semver) and only on explicit request.
  After tagging, watch the run and report per-channel results (GitHub Release,
  npm, Homebrew tap).

---

## 5. When you're unsure

- If a change would loosen the security posture, alter the threat model, or
  touch the release/publish path — **stop and ask.** These have blast radius
  beyond the working tree.
- If a fact here appears stale (a pinned version, a repo/scope name, a file
  path), verify it against the actual file before acting, and flag the drift.
- Prefer asking one sharp question over guessing on anything user-facing or
  published.
