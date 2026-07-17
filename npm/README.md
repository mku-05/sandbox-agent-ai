# @mku-05/agent-sandbox

Run Claude Code, OpenAI Codex, or GitHub Copilot CLI inside a locked-down
Docker container so an agent can do anything inside a chosen folder and nothing
else on your filesystem.

> **Requires Docker on the host.** This npm package only installs the
> `agent-sandbox` launcher; the agent CLIs themselves run inside the container.

## Install

```bash
npm i -g @mku-05/agent-sandbox
```

## Usage

```bash
agent-sandbox claude  /path/to/project
agent-sandbox codex   /path/to/project
agent-sandbox copilot /path/to/project

# folder defaults to the current directory:
cd /path/to/project && agent-sandbox claude
```

See the full documentation and threat model at
<https://github.com/mku-05/sandbox-agent-ai>.
