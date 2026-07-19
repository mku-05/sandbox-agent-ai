# Verify skill for agent-sandbox

Surface: `agent-sandbox.sh` is a CLI shell script. No server or GUI — the surface is the terminal.

## Build / install

None needed. Run directly with `bash agent-sandbox.sh ...` from repo root.

## Driving the surface

`--dry-run` is the key handle — it prints the docker command(s) without launching Docker or needing a live image. Use it to exercise all flag paths without needing Docker running:

```bash
bash agent-sandbox.sh claude --dry-run          # open mode (default)
bash agent-sandbox.sh claude --net=none --dry-run
bash agent-sandbox.sh claude --net=allowlist --dry-run
bash agent-sandbox.sh claude --allow=example.com --dry-run
```

Always capture exit code: `; echo "EXIT=$?"`. With `set -euo pipefail` in the script, trap functions that end on a failing test propagate exit 1.

## Flows worth driving

1. Flag parsing: unknown flag, invalid --net, extra arg → each should print a clear error and exit 1
2. `--dry-run` with all three `--net` modes → should exit 0 and print the docker command
3. `--allow=<domain>` → should appear in the allowed-domains list and imply allowlist mode
4. No agent arg → should print usage and exit 1

## Gotchas

- `cleanup_net` is registered as an EXIT trap. With `set -e`, if the trap function's last executed command exits non-zero, the script exits non-zero even after `exit 0`. Watch for `[ -n "" ]`-style false tests at the end of the trap body.
- `--dry-run` skips Docker availability check and secrets-file creation, so it works on any machine.
