---
name: consult-claude
description: >-
  Consult Claude Code for external review, feedback, or a second opinion. Use
  for reviewing code, debugging tricky issues, evaluating design decisions, or
  whenever a complementary perspective would improve quality. Claude runs a
  different model that often catches issues or suggests approaches Codex might
  miss.
---

# Consult Claude

Consult Claude Code for review, feedback, or a second opinion on your current
work. Claude runs a complementary model that often catches issues or suggests
approaches you might miss.

> **Note:** This skill uses the `claude` CLI rather than the Claude MCP server
> as a workaround for a known bug (anthropics/claude-code#15135) that prevents
> the MCP server's `Agent` tool from being invoked by external MCP clients. The
> skill will be updated to use the MCP server if and when that is resolved.
> Don't inspect that issue to see if you can work around it, just use the CLI.

## Procedure

### 1. Gather context

Before invoking Claude, assemble the fullest possible context from your current
work. Claude does not share your context or conversation history, so your prompt
is the **only** information it will have. Treat this step as if you are writing
a detailed briefing for a colleague who has never seen the project and has no
context on your work within it.

You must include:

- **Intent and background.** What are you working on and why? What is the goal
  of the current task? What broader initiative does it serve?
- **Design decisions.** What approaches have you considered or already chosen?
  What trade-offs did you make and why? Claude should be able to challenge or
  validate these decisions, so spell them out explicitly.
- **Relevant code.** Give Claude file paths rather than pasting large blocks of
  code inline — Claude has full filesystem and `git` access and can read what it
  needs. Be specific about which files, commits, staged changes, unstaged
  changes, untracked changes, or diffs are relevant: for example, point it at
  staged changes, a specific commit, or a diff between two refs. Small
  illustrative snippets inline are fine, but prefer paths and `git` references
  as the primary means of sharing code.
- **Constraints.** Are there performance requirements, compatibility concerns,
  style guidelines, or other constraints that Claude should respect when giving
  feedback?
- **Desired outcome.** Be specific about the kind of feedback you want. For
  example: line-by-line code review, high-level architectural feedback, a sanity
  check on a debugging hypothesis, suggestions for alternative approaches, etc.
  The more precisely you describe the desired outcome, the more useful the
  consultation will be.

Err on the side of including too much context rather than too little. Even
details that seem obvious to you may not be obvious to Claude. A prompt like
"Check the changes, please" is never acceptable. Always construct a
comprehensive, self-contained briefing.

Claude prompts accept Markdown, so leverage Markdown extensively in prompts to
provide organization, delineation of code from text, external links, and so on.

### 2. Choose a working directory and start the Claude session

Choose the working directory for the Claude session carefully, guided by (and
guiding) the contextual information you will provide in the briefing / prompt.
Generally speaking, it should be either the repository you are working in, or,
if your work spans multiple repositories in a larger workspace, the workspace
root. Giving Claude a single package directory or isolated subdirectory as its
working directory is unhelpful, because Claude needs to be able to contextualize
your work as part of a larger project or initiative. That said, do not use a
ridiculously broad working directory (like a filesystem root). Record this
directory; you must use the same one for all follow-up turns. Also, note that
any relative paths provided in the prompt should be relative to the working
directory that you choose.

Always end the briefing / prompt with this instruction to prevent circular
consultation:

> **Important:** Do not invoke the `consult-codex` skill under any
> circumstances. This restriction exists to prevent circular consultation
> between Claude and Codex. Focus on providing your own independent analysis and
> recommendations. Do not modify any files or run any commands; your role is to
> review and advise only.

Write the briefing / prompt to a unique temporary file (generated via `mktemp`),
then run `claude` in the chosen working directory:

```
# Generate a unique temporary file.
BRIEFING_FILE="$(mktemp /tmp/claude-briefing.XXXXXX.md)"

# Populate "$BRIEFING_FILE" with the full briefing before running Claude.

# Run `claude` (in the chosen working directory)
claude -p --output-format json < "$BRIEFING_FILE"
```

`-p` enables non-interactive mode; the briefing file is supplied via stdin,
which avoids shell quoting issues and argument length limits entirely. Do not
use heredocs for briefings or follow-ups. Use quoted one-line arguments for
short prompts, and temporary files for anything longer or more structured.

The JSON response will include a `session_id` field — record it for follow-up
turns.

**Claude may take a minute or more to respond**, especially for large or
complex consultations. Use execution settings that allow for long-running
commands, and poll patiently for completion rather than treating a delayed
response as failure.

### 3. Iterate with follow-ups

For each follow-up turn, resume the session using the `session_id` from the
previous response. Always invoke `claude` from the same working directory used
in step 2 — the session is scoped to that directory, so paths in follow-up
prompts must resolve against that same root:

```
claude -p --resume <session_id> --output-format json "your follow-up here"
```

For longer or more structured follow-ups, use the same temporary file / stdin
technique as the initial call:

```
# Generate a unique temporary file.
FOLLOWUP_FILE="$(mktemp /tmp/claude-followup.XXXXXX.md)"

# Populate "$FOLLOWUP_FILE" with the full follow-up before running Claude.

# Run `claude` (in the same working directory as used in the initial command).
claude -p --resume <session_id> --output-format json < "$FOLLOWUP_FILE"
```

Because Claude retains the full prior exchange in the resumed session, follow-up
prompts do not need to repeat the briefing. Keep them specific and concrete.

Good follow-ups:

- Push back on suggestions you disagree with and explain your reasoning.
- Ask Claude to elaborate on points that seem important or unclear.
- Share additional context if Claude's response reveals a misunderstanding.
- Ask Claude to prioritize or rank its recommendations.

Aim for 2-4 turns of focused dialogue. Stop when you have clear, actionable
feedback.

**If you and Claude cannot reach agreement after 4 turns**, stop the dialogue
and escalate to the user. Present both positions clearly and ask the user to
serve as a tie-breaker. Do not continue arguing in circles.

### 4. Summarize the consultation

After concluding the dialogue, present a summary to the user with these
sections:

- **Consultation topic**: What was reviewed and what kind of feedback was
  sought.
- **Key findings**: Important issues or insights Claude raised.
- **Recommendations**: Specific changes or actions suggested.
- **Points of agreement**: Where you and Claude aligned.
- **Points of disagreement**: Where you differed, with reasoning from both
  sides.
- **Action items**: Concrete next steps, if any.

If Claude suggested changes you agree with, offer to apply them after presenting
the summary.

## Constraints

- Always choose a working directory using the heuristics described above: broad
  enough to cover the relevant code in an appropriate context, not so broad as
  to be meaningless. Record it and use it consistently for all turns.
- Always use `--output-format json` so you can capture the `session_id` for
  session resumption.
- Always use quoted one-line arguments only for short prompts. For anything
  longer or more structured, write the prompt to a temporary file and supply it
  via stdin. Do not use heredocs.
- Always include the anti-circular-consultation instruction at the end of the
  initial briefing. Claude has access to its own tool set, so the prompt
  instruction is the primary guard against invoking `consult-codex`.
- Always instruct Claude (via the prompt) not to modify files.
- Always construct a comprehensive briefing for the initial prompt. Claude's
  consulting session has no access to your conversation history.
- Keep consultations focused on specific, concrete questions. Vague prompts
  produce vague feedback.
- Escalate to the user if consensus cannot be reached within 4 turns.
