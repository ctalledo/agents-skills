# Agent Tools

This repository contains directives, skills, agents, and tools for use with
agentic coding assistants such as OpenAI Codex and Claude Code.

It is designed to distribute and track revisions to the tools. It offers an
`install.sh` script that, once the repository is cloned, provides automatic
installation via symlinking into user-level agent configuration directories.

## General Setup

Many skills in this repository require that the `gh` CLI tool be installed and
authenticated. Using a `GITHUB_TOKEN` environment variable is a great approach
to authentication for the `gh` tool.

## Claude Setup

The following steps are required and/or recommended for using the skills and
agents defined in this repository:

### Disable `claude.ai` MCP Servers (Optional)

For security reasons, you may wish to disable the built-in `claude.ai` MCP
servers that automatically propagate from your cloud-based Claude account. You
can do this by adding the following to your shell initialization scripts (e.g.
`~/.bashrc`):

```shell
# Disable claude.ai MCP servers from automatically propagating to Claude Code.
export ENABLE_CLAUDEAI_MCP_SERVERS="false"
```

### Optimal Model Usage

The best model setup for Claude Code is to use Opus for Plan Mode and Sonnet for
plan execution. To enable this combination (with automatic switching), enter
Claude Code and run the following command:

```
/model opusplan
```

If you'd like, you can also use the left / right arrows to adjust the effort
level, though leaving the default "Medium" level is recommended.

### Disable Attribution in Commits and PRs (Optional)

To disable Claude Code co-authorship in commit messages and PRs, set the
following in `~/.claude/settings.json`:

```json
{
    "attribution": {
        "commit": "",
        "pr": ""
    }
}
```

### Recommended Plugins

The following plugins are recommended from the default `claude-plugins-official`
marketplace:

- `code-simplifier`
- `frontend-design`
- `gopls-lsp`
- `skill-creator`
- `typescript-lsp`

You can search for and install them by entering Claude Code and running:

```
/plugin
```

For all plugins, the recommended installation scope is "user scope".

### Skill Allowance

For convenience, you may also wish to auto-enable use of the skills from this
repository in `~/.claude/settings.json`:

```json
{
    "permissions": {
        "allow": [
            "Skill(consult-codex)",
            "Skill(review-plan-as-ceo)",
            "Skill(review-plan-as-em)",
            "Skill(drive-pr)",
            "Skill(fix-ci)",
            "Skill(review-pr)"
        ]
    }
}
```

### Codex MCP Setup

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

### Chrome DevTools Plugin / MCP Setup

The built-in `claude-plugins-official` marketplace provides a Chrome DevTools
plugin (`chrome-devtools-mcp`), but it's better to use the version from the
[upstream repository](https://github.com/ChromeDevTools/chrome-devtools-mcp),
which maintains its own `chrome-devtools-plugins` marketplace with the latest
version of `chrome-devtools-mcp` with more skills and less context usage.

To enable the upstream marketplace, enter Claude Code and run:

```
/plugin marketplace add ChromeDevTools/chrome-devtools-mcp
```

Because the plugins from both marketplaces share the same name, it's best to run
`/plugin`, search for `chrome-devtools-plugins`, and install the one from the
`chrome-devtools-plugins` marketplace (rather than using
`/plugin install chrome-devtools-mcp`).

The recommended installation scope is "user scope".

For convenience, you may also wish to auto-enable use of this server in
`~/.claude/settings.json`:

```json
{
    "permissions": {
        "allow": [
            "mcp__plugin_chrome-devtools-mcp_chrome-devtools"
        ]
    }
}
```

## Installation

To install the directives, skills, agents, and tools in this repository, run the
installation script:

```shell
./install.sh
```

Note that you'll need to re-run it if you ever relocate the repository, and
possibly also on updates.

## Repository Setup

Several of the skills in this repository will create files in a folder called
`.agent-state` in the root of the repositories where they operate. You may wish
to add this location to your `.gitignore` file, for example:

```
.agent-state/
```
