# Agent Tools

This repository contains directives, skills, and tools for AI agents such as
OpenAI Codex and Claude Code.

It is designed to distribute and track revisions to the tools. It offers an
`install.sh` script that, once the repository is cloned, provides automatic
installation via symlinking into user-level agent configuration directories.

## General Setup

Many skills in this repository require that the `gh` CLI tool be installed and
authenticated. Using a `GITHUB_TOKEN` environment variable is a great approach
to authentication for the `gh` tool.

## Claude Setup

The `consult-codex` skill installed by this repository requires the Codex MCP
server to be added to Claude Code:

```
claude mcp add --scope user codex -- codex mcp-server
```

For convenience, you may also wish to auto-enable use of this server in
`~/.claude/settings.json`:

```json
{
    "permissions": {
        "allow": [
            "mcp__codex"
        ]
    }
}
```

## Codex Setup

The `consult-claude` skill installed by this repository requires the `claude`
CLI and certain Claude configuration directories to be available to Codex so it
can persist consultation sessions. You can enable that directory access in
`~/.codex/config.toml`:

```toml
[sandbox_workspace_write]
writable_roots = [
  # Adjust paths to your home directory.
  "/Users/jacob/.claude",
  "/Users/jacob/.claude.json"
]
```
