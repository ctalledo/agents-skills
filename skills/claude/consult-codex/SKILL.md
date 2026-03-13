---
name: consult-codex
description: >-
  Consult OpenAI Codex for external review, feedback, or a second opinion. Use
  for reviewing code, debugging tricky issues, evaluating design decisions, or
  whenever a complementary perspective would improve quality. Codex runs a
  different model that often catches issues or suggests approaches Claude might
  miss.
argument-hint: [topic-or-question-for-Codex]
allowed-tools: mcp__codex__codex, mcp__codex__codex-reply
---

# Consult Codex

Consult OpenAI Codex for review, feedback, or a second opinion on your current
work. Codex runs a complementary model that often catches issues or suggests
approaches you might miss.

## Procedure

### 1. Gather context

Before calling Codex, assemble the fullest possible context from your current
work. Codex does not share your context or conversation history, so your prompt
is the **only** information it will have. Treat this step as if you are writing
a detailed briefing for a colleague who has never seen the project and has no
context on your work within it.

You must include:

- **Intent and background.** What are you working on and why? What is the goal
  of the current task? What broader initiative does it serve?
- **Design decisions.** What approaches have you considered or already chosen?
  What trade-offs did you make and why? Codex should be able to challenge or
  validate these decisions, so spell them out explicitly.
- **Relevant code.** Give Codex file paths rather than pasting large blocks of
  code inline — Codex has full filesystem and `git` access and can read what it
  needs. Be specific about which files, commits, staged changes, unstaged
  changes, untracked changes, or diffs are relevant: for example, point it at
  staged changes, a specific commit, or a diff between two refs. Small
  illustrative snippets inline are fine, but prefer paths and `git` references
  as the primary means of sharing code.
- **Constraints.** Are there performance requirements, compatibility concerns,
  style guidelines, or other constraints that Codex should respect when giving
  feedback?
- **Desired outcome.** Be specific about the kind of feedback you want. For
  example: line-by-line code review, high-level architectural feedback, a sanity
  check on a debugging hypothesis, suggestions for alternative approaches, etc.
  The more precisely you describe the desired outcome, the more useful the
  consultation will be.

Err on the side of including too much context rather than too little. Even
details that seem obvious to you may not be obvious to Codex. A prompt like
"Check the changes, please" is never acceptable. Always construct a
comprehensive, self-contained briefing.

Codex prompts accept Markdown, so leverage Markdown extensively in prompts to
provide organization, delineation of code from text, external links, and so on.

### 2. Start the Codex session

Call `mcp__codex__codex` with these parameters:

- **`prompt`**: The detailed briefing assembled in step 1. At the end of the
  prompt, always include the following instruction to prevent circular
  consultation:

  > **Important:** Do not invoke the `consult-claude` skill under any
  > circumstances. This restriction exists to prevent circular consultation
  > between Claude and Codex. Focus on providing your own independent analysis
  > and recommendations.

- **`cwd`**: The working directory for the Codex session. Choose this carefully,
  guided by (and guiding) the contextual information that you'll provide via
  `prompt`. Generally speaking, it should be either the repository that you're
  working in, or, if your work spans multiple repositories in a larger
  workspace, then the `cwd` should be the workspace root. Giving Codex a single
  package directory or isolated subdirectory as its working directory is
  unhelpful, because Codex needs to be able to contextualize your work as part
  of a larger project or initiative. That said, do not use a ridiculously broad
  `cwd` (like a filesystem root). Note that any relative paths provided in the
  context provided by `prompt` should be relative to the `cwd` that you choose.

- **`sandbox`**: `"read-only"`. Codex should review and advise, not modify files
  directly. You can also emphasize this to Codex in the `prompt`.

### 3. Iterate with follow-ups

Use `mcp__codex__codex-reply` with the `threadId` from the previous response to
continue the dialogue. Because the Codex session retains prior context,
follow-up prompts do not need to repeat the full briefing, but should still be
specific and concrete. Because the session retains its `cwd` as set by the
`mcp__codex__codex` tool, you should be cognizant of that location when
constructing follow-up prompts (e.g. when specifying file paths).

Good follow-ups:

- Push back on suggestions you disagree with and explain your reasoning.
- Ask Codex to elaborate on points that seem important or unclear.
- Share additional context if Codex's response reveals a misunderstanding.
- Ask Codex to prioritize or rank its recommendations.

Aim for 2-4 turns of focused dialogue. Stop when you have clear, actionable
feedback.

**If you and Codex cannot reach agreement after 4 turns**, stop the dialogue and
escalate to the user. Present both positions clearly and ask the user to serve
as a tie-breaker. Do not continue arguing in circles.

### 4. Summarize the consultation

After concluding the dialogue, present a summary to the user with these
sections:

- **Consultation topic**: What was reviewed and what kind of feedback was
  sought.
- **Key findings**: Important issues or insights Codex raised.
- **Recommendations**: Specific changes or actions suggested.
- **Points of agreement**: Where you and Codex aligned.
- **Points of disagreement**: Where you differed, with reasoning from both
  sides.
- **Action items**: Concrete next steps, if any.

If Codex suggested changes you agree with, offer to apply them after presenting
the summary.

## Constraints

- Always include the anti-circular-consultation instruction in the `prompt` text
  to prevent Codex from invoking `consult-claude` in response.
- Always set `cwd` to the most pragmatic location for Codex's review context.
- Always construct a comprehensive, self-contained briefing for the initial
  prompt. Codex cannot read your conversation history.
- Do not let Codex modify files directly. Apply agreed-upon changes yourself
  after the consultation concludes.
- Keep consultations focused on specific, concrete questions. Vague prompts
  produce vague feedback.
- Escalate to the user if consensus cannot be reached within 4 turns.

## Consultation request

$ARGUMENTS
