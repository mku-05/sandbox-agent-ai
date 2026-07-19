# CLAUDE.md

**Read [`AGENTS.md`](./AGENTS.md) and follow it.** It is the single source of
truth for all coding agents in this repo. This file exists only to point you
there — there are no Claude-specific instructions that override it.

Hard rules you must not miss (full context in `AGENTS.md`):

- **No AI attribution** in commits or PRs — no `Co-Authored-By` trailer, no
  `🤖 Generated with …` footer.
- **Never commit/push to `main`** — always branch (`feat/…` or `fix/…`);
  merge via PR.
- **`@mku0502` (npm scope) ≠ `mku-05` (GitHub owner)** — do not conflate them.
- **Tag a release only when explicitly asked** — `v*` tags publish publicly.

A `/ship` skill automates branch → commit → PR → (optional) release. Prefer it.
