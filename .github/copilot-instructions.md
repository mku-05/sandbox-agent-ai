# GitHub Copilot instructions

**Read [`../AGENTS.md`](../AGENTS.md) and follow it.** It is the single source of
truth for all coding agents in this repo. This file only points you there; there
are no Copilot-specific rules that override it.

Hard rules you must not miss (full context in `AGENTS.md`):

- **No AI attribution** in commits or PRs — no `Co-Authored-By` trailer, no
  `🤖 Generated with …` footer.
- **Never commit/push to `main`** — always branch (`feat/…` or `fix/…`);
  merge via PR.
- **`@mku0502` (npm scope) ≠ `mku-05` (GitHub owner)** — do not conflate them.
- **Tag a release only when explicitly asked** — `v*` tags publish publicly.
