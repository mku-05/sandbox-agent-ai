# Homebrew formula for agent-sandbox.
#
# This file is the source of truth for the formula. On each tagged release the
# GitHub Actions workflow rewrites `version`, `url`, and `sha256` below and
# pushes the result to the tap repo (mku-05/homebrew-tap), so users can:
#
#   brew install mku-05/tap/agent-sandbox
#
# `docker` isn't a Homebrew-installable dependency (it's Docker Desktop / engine
# on most hosts), so we surface it via caveats rather than `depends_on`.
class AgentSandbox < Formula
  desc "Run Claude Code, OpenAI Codex, or GitHub Copilot CLI in a locked-down Docker sandbox"
  homepage "https://github.com/mku-05/sandbox-agent-ai"
  version "0.0.0"
  url "https://github.com/mku-05/sandbox-agent-ai/releases/download/v0.0.0/agent-sandbox"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  def install
    bin.install "agent-sandbox"
    # Back-compat for anyone who still types the old `.sh` name.
    bin.install_symlink "agent-sandbox" => "agent-sandbox.sh"
  end

  def caveats
    <<~EOS
      agent-sandbox requires Docker on the host (the agent CLIs run inside the
      container). If you don't have it:
        https://www.docker.com/
    EOS
  end

  test do
    assert_match "agent-sandbox #{version}", shell_output("#{bin}/agent-sandbox --version")
  end
end
