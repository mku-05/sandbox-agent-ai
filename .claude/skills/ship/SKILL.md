---
name: ship
description: >-
  Ship a change end-to-end for this repo (sandbox-agent-ai): branch, commit,
  push, open a PR, and — when a release is wanted — tag it so the multi-channel
  install (curl / Homebrew / npm) deploys. Use whenever the user says "ship
  this", "commit and PR", "raise a PR", "cut a release", or "deploy it".
---

# Ship a change end-to-end

This repo ships one launcher (`agent-sandbox`) through three install channels —
**curl**, **Homebrew**, and **npm** — all driven off tagged GitHub Releases.
Follow this to take a change from working tree to deployed.

## Hard rules (do not deviate)

- **No AI attribution, ever.** Do NOT add `Co-Authored-By: Claude …` to commits
  or `🤖 Generated with Claude Code` to PR bodies. The user has explicitly
  required this for this repo.
- **Never commit/push directly to `main`.** Always branch. `main` is
  PR-merge-only.
- **Never commit build output.** `dist/` and `npm/bin/` are gitignored and are
  produced by CI; keep it that way.
- **Confirm before releasing.** Cutting a tag publishes publicly (GitHub Release
  + npm + Homebrew tap). Push code freely, but only tag when the user says so.

## Conventions

- **Branch names:** `feat/<slug>` for features, `fix/<slug>` for fixes.
- **Repo (GitHub owner):** `mku-05/sandbox-agent-ai`. Homebrew tap:
  `mku-05/homebrew-tap`.
- **npm scope is different from the GitHub owner:** the package is
  `@mku0502/agent-sandbox` (scope `@mku0502`), NOT `@mku-05`. `mku-05` is only
  the GitHub owner / repo / tap / release-URL namespace. Never conflate them.
- **Commit message:** short imperative subject; body explains *why* + a terse
  bullet list of *what*. No attribution trailer.

## Steps

### 1. Verify the change actually works
Run the relevant checks before committing — don't just claim it works:
```bash
bash -n agent-sandbox.sh install.sh scripts/build-release.sh   # shell syntax
ruby -c Formula/agent-sandbox.rb                               # formula
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"  # workflow YAML
python3 -c "import json;json.load(open('npm/package.json'))"   # package.json
bash scripts/build-release.sh 0.0.0 dist && bash dist/agent-sandbox --version && rm -rf dist
```
If the Docker daemon is up, sanity-check the embedded Dockerfile:
```bash
rm -rf dist && bash scripts/build-release.sh 0.0.0 dist
# reproduce what the installed tool pipes to docker build:
EMBEDDED_DOCKERFILE=1 SCRIPT_DIR=/nonexistent bash -c "$(sed -n '/^emit_dockerfile()/,/^}/p' dist/agent-sandbox); emit_dockerfile" | docker build --check -
rm -rf dist
```

### 2. Branch, ensure scripts stay executable, commit
```bash
git checkout -b feat/<slug>          # or fix/<slug>
chmod +x agent-sandbox.sh install.sh scripts/build-release.sh
git add -A
git commit -F - <<'EOF'
<imperative subject line>

<why this change exists>
- <what changed, terse>
EOF
# Confirm the three scripts are staged as mode 100755:
git ls-files -s agent-sandbox.sh install.sh scripts/build-release.sh
```

### 3. Push and open the PR
```bash
git push -u origin <branch>
gh pr create --base main --head <branch> --title "<subject>" --body "$(cat <<'EOF'
## What
<one-paragraph summary>

## Changes
- <bullet per file/area>

## Verification
- <what you actually ran and observed>
EOF
)"
```
No `🤖` footer. Report the PR URL back to the user.

### 4. After merge — sync and clean up
```bash
git checkout main && git pull --ff-only origin main
git branch -d <branch>
git push origin --delete <branch>
```

### 5. Release (ONLY when the user asks to deploy/cut a release)
Tags matching `v*` trigger `.github/workflows/release.yml`:
`build → GitHub Release → npm-publish → homebrew-bump`.
```bash
git checkout main && git pull --ff-only origin main
git tag vX.Y.Z            # semver; increment from the latest tag
git push origin vX.Y.Z
```
Then watch the run and report per-job results:
```bash
gh run list --repo mku-05/sandbox-agent-ai --limit 1
gh run view <run-id> --repo mku-05/sandbox-agent-ai
```

### 6. Confirm the deploy landed (all three channels)
```bash
gh release view vX.Y.Z --repo mku-05/sandbox-agent-ai --json assets -q '.assets[].name'
gh api repos/mku-05/homebrew-tap/contents/Formula/agent-sandbox.rb -q '.content' | base64 -d | grep -E 'version|sha256'
npm view @mku0502/agent-sandbox version
```
All three should reflect the new version.

## Prerequisites (already set up — verify only if a channel fails)
- Secrets on `mku-05/sandbox-agent-ai`: `NPM_TOKEN`, `HOMEBREW_TAP_TOKEN`
  (`gh secret list --repo mku-05/sandbox-agent-ai`).
- `mku-05/homebrew-tap` repo exists.

## Troubleshooting the release workflow
- **npm 403 "Two-factor authentication … required"** — the `NPM_TOKEN` is a
  granular token WITHOUT "Bypass 2FA" enabled. Regenerate it on npmjs.com with
  bypass-2FA checked (scoped read/write to `@mku0502`), then
  `gh secret set NPM_TOKEN --repo mku-05/sandbox-agent-ai`.
- **Re-run without a new tag:** after fixing a secret,
  `gh run rerun <run-id> --repo mku-05/sandbox-agent-ai --failed`. build +
  homebrew jobs are idempotent; npm retries the publish.
- **npm/brew jobs skipped** — their secret is unset; the job gates on it and
  no-ops. curl + GitHub Release still succeed.
