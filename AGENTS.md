# Agent Tools

This repository contains directives, skills, and tools for AI agents such as
OpenAI Codex and Claude Code.

It is designed to distribute and track revisions to these tools. It provides an
`install.sh` script that, once the repository is cloned, enables automatic
installation via symlinking into user-level agent configuration directories.

It currently has the following items:

- `directives/common.md`: This file gets symlinked into user-level agent
  configuration directories as an `AGENTS.md` or `CLAUDE.md` file (depending on
  the agent in question). It contains code style guidelines and basic workflow
  guidelines that are appropriate across projects.
- `skills`: This directory contains skills that get symlinked into user-level
  agent skills directories. The skills are divided into those specific to Codex
  (in `skills/codex`), those specific to Claude Code (in `skills/claude`), and
  those common to all agents (in `skills/common`). The following skills are
  currently defined:
    - `skills/codex/consult-claude`: A skill that enables Codex to consult
      Claude Code for additional review, feedback, and assistance.
    - `skills/claude/consult-codex`: A skill that enables Claude Code
      to consult Codex for additional review, feedback, and assistance.
