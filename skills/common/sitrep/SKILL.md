---
name: sitrep
description: >-
  Run a situational report: check all notification sources, correlate findings,
  update the worklog, and present a summary of current work threads and action
  items. Use "quick" to skip source checks and just display current state.
disable-model-invocation: true
argument-hint: "[quick]"
compatibility: >-
  Requires gh CLI, gws CLI, Slack MCP, Linear MCP, and Atlassian MCP. Requires
  the wl tool in the worklog repository.
---

# Situational Report (Sitrep)

If `$ARGUMENTS` is `quick`, skip to Step 6 (Present the
sitrep) in the procedure below and display the current
worklog state without checking notification sources.

Follow the full sitrep procedure in
`~/.claude-procedures/sitrep.md`.

## Target

$ARGUMENTS
