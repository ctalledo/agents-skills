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
- `agents`: This directory contains subagent definitions for agents that
  support autonomous (non-interactive) operation. Currently only Claude Code
  subagents are defined, under `agents/claude`. Each agent has its own
  subdirectory containing an `AGENT.md` file with frontmatter (name,
  description, model, permissionMode, skills) and a system prompt body. The
  following agents are currently defined:
    - `agents/claude/ci-fixer`: Autonomous CI diagnosis and local fixing.
      Applies code fixes without approval gates; stops before committing or
      pushing.
    - `agents/claude/pr-reviewer`: Autonomous PR review. Returns a complete
      findings-first report without posting anything to GitHub.
- `skills`: This directory contains skills that get symlinked into user-level
  agent skills directories. The skills are divided into those specific to Codex
  (in `skills/codex`), those specific to Claude Code (in `skills/claude`), and
  those common to all agents (in `skills/common`). The following skills are
  currently defined:
    - `skills/claude/review-plan-as-ceo`: A skill for reviewing an
      implementation plan as a visionary CEO, challenging premises, mapping
      the dream state, and performing a comprehensive 10-section technical
      review.
    - `skills/claude/review-plan-as-em`: A skill for reviewing an
      implementation plan as a pragmatic engineering manager, focusing on
      scope, architecture, code quality, tests, and performance.
    - `skills/common/drive-pr`: A skill for driving a GitHub pull request
      toward completion by identifying blockers and executing the next
      high-leverage follow-up work.
    - `skills/common/fix-ci`: A skill for diagnosing and fixing failing CI
      checks on a branch or pull request.
    - `skills/common/review-pr`: A skill for reviewing a GitHub pull request
      and preparing a findings-first report.

## Commit Messages

When creating commits in this repository, use a short area prefix, then a
single colon, then a space, then a brief description. Common prefixes include
`docs`, `agents`, `skills`, `tools`, and `scripts`.

If a prefix benefits from more specificity, include a target in parentheses,
for example `skills(review-pr): improve inline comment formatting` or
`tools(install): handle missing target directories`.

Prefer the prefix that best matches the primary area being changed. For
directive-related changes, use `agents`. For documentation-only changes such
as `README.md`, use `docs`. For skill-related changes, use `skills`.

Keep the subject line brief, then include a full commit message body below it.
The body can be as detailed as needed and should explain context, rationale,
notable implementation details, and any follow-up considerations.
