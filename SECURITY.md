# Security Policy

`agent-sandbox` is a security tool, so its own threat model is part of the
product. Please read this before filing a report — some "issues" are documented,
intentional trade-offs.

## What the sandbox does and does not protect

The container isolates the **filesystem** and **scopes credentials**. Network
isolation is **opt-in**: by default (`--net=open`) outbound network is open
because the agents must reach Bedrock / OpenAI / GitHub. Run
`--net=allowlist` to limit egress to known hosts, or `--net=none` for offline.

| Concern | Protected? |
|---|---|
| Agent editing/deleting files outside the target folder | ✅ Yes — only `/workspace` is mounted |
| Agent creating root-owned files on the host | ✅ Yes — runs as non-root `node` (uid 1000) |
| Privilege escalation inside the container | ✅ Mostly — `--cap-drop=ALL`, `--security-opt=no-new-privileges` |
| Fork bombs / memory exhaustion | ✅ Bounded — `--pids-limit`, `--memory` |
| Secrets leaking from your shell env | ✅ Yes — secrets come from a file, never your shell rc |
| Agent exfiltrating data over the network | ⚠️ Optional — open by default; `--net=allowlist` limits egress, `--net=none` blocks it |
| Agent reading your AWS creds (`claude` only) | ⚠️ Partial — mounted read-only; use short-lived SSO creds |

If a report boils down to "the agent could send data over the network **with
`--net=open`**" or "a long-lived AWS key could be read," that is a **known,
documented limitation**, not a vulnerability. Mitigate it with
`--net=allowlist` and by scoping credentials (prefer `aws sso login` /
short-lived creds) rather than relying on the container.

A genuine bug *would* be egress escaping the allowlist in `--net=allowlist`
mode (e.g. a way to reach a non-allowlisted host, or bypass the proxy) — please
do report that.

## What *is* an in-scope vulnerability

Report these:

- A container **filesystem escape** — the agent writing outside `/workspace` on
  the host, or reading host paths that aren't mounted.
- **Privilege escalation** to root inside the container, or bypass of
  `no-new-privileges` / the dropped capabilities.
- Secrets from `~/.secrets/agent-sandbox.env` or the AWS mount leaking to a
  place the design says they shouldn't reach.
- A flaw in the **install/release path** — e.g. the checksum verification in
  `install.sh` being bypassable, or the embedded-Dockerfile build being
  poisonable.
- Any way the launcher can be tricked into mounting an unintended host path
  (the `$HOME` / `/` guardrail being bypassable).

## Reporting

Please **do not open a public GitHub issue** for a suspected vulnerability.

Use GitHub's **private vulnerability reporting**:
**Security → Report a vulnerability** on
<https://github.com/mku-05/sandbox-agent-ai/security/advisories/new>.

Include: affected version (`agent-sandbox --version`), your OS and Docker
version, and the smallest set of steps that reproduces the issue. A proof of
concept helps enormously.

## Supported versions

This is a single self-contained artifact with no long-term support branches.
Fixes land on `main` and ship in the next tagged release; please verify against
the latest release before reporting.
