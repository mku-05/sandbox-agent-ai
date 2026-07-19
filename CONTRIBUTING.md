# Contributing to agent-sandbox

Thanks for considering a contribution! This is a small, security-focused project
— one bash launcher shipped through three install channels. That minimalism is
deliberate, so the bar for changes is "smallest correct diff that keeps the
security posture honest."

If you're an **AI coding agent**, read [`AGENTS.md`](./AGENTS.md) first — it is
the authoritative operating manual and its rules override anything here.

## Ground rules

- **Branch, never push to `main`.** Use `feat/<slug>` or `fix/<slug>`; `main` is
  merge-via-PR only.
- **No AI-attribution trailers/footers** in commits or PRs (`Co-Authored-By`,
  `🤖 Generated with …`). This is a hard project requirement.
- **Don't commit build output.** `dist/` and `npm/bin/` are gitignored and
  produced by CI.
- **Don't loosen the security posture silently.** The hardening flags
  (`--cap-drop=ALL`, `--security-opt=no-new-privileges`, pid/memory caps,
  non-root user, read-only AWS mount) exist for reasons documented inline. If a
  change affects what is or isn't protected, update the threat-model table in
  the [README](./README.md) in the same PR.
- **Pin, don't float.** Base image and agent CLI versions are pinned on purpose.
  Bump them deliberately, never to a floating `latest`.

## Setting up

The only host dependency for *using* the tool is Docker. For *developing* it you
also want `bash`, and — to run the full check suite locally — `ruby` (formula &
YAML/JSON checks) and optionally `shellcheck` and a running Docker daemon.

## Before you open a PR

Run the checks relevant to what you touched (this is exactly what CI runs):

```bash
# Shell syntax (any *.sh change)
bash -n agent-sandbox.sh install.sh scripts/build-release.sh

# Lint (optional locally; CI enforces it)
shellcheck agent-sandbox.sh install.sh scripts/build-release.sh

# Homebrew formula (if Formula/ changed)
ruby -c Formula/agent-sandbox.rb

# Workflow YAML (if .github/ changed)
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"

# npm metadata (if npm/ changed)
ruby -rjson -e "JSON.parse(File.read('npm/package.json'))"

# End-to-end: build the artifact and confirm it stamps + runs
bash scripts/build-release.sh 0.0.0 dist && bash dist/agent-sandbox --version && rm -rf dist
```

If you changed the `Dockerfile` or the embed logic and have Docker running,
validate the *embedded* Dockerfile the way the shipped tool emits it:

```bash
rm -rf dist && bash scripts/build-release.sh 0.0.0 dist
EMBEDDED_DOCKERFILE=1 SCRIPT_DIR=/nonexistent \
  bash -c "$(sed -n '/^emit_dockerfile()/,/^}/p' dist/agent-sandbox); emit_dockerfile" \
  | docker build --check -
rm -rf dist
```

Keep the three scripts executable (mode `100755`) — confirm with
`git ls-files -s agent-sandbox.sh install.sh scripts/build-release.sh`.

## Commit & PR format

- **Commit:** short imperative subject; body explains *why* plus a terse bulleted
  *what*. No attribution trailer.
- **PR body:** use `## What` / `## Changes` / `## Verification`, and state what
  you actually ran and observed.

## Reporting security issues

Please do **not** open a public issue for a vulnerability — see
[`SECURITY.md`](./SECURITY.md).
