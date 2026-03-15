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
# Generate unique temporary files. Use a template with trailing Xs so this
# works on BSD/macOS `mktemp` as well as GNU `mktemp`.
BRIEFING_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-briefing.XXXXXX")"
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-output.XXXXXX")"
PID_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-pid.XXXXXX")"

# Populate "$BRIEFING_FILE" with the full briefing before running Claude.
# Record these exact paths in your own notes or outer execution context before
# launching Claude. You may need them while the command is still running.

# Run `claude` in the background, capture its stdout to a file, and record
# its PID so that you can enforce a timeout if needed. The saved output file
# is the authoritative record of Claude's response if your outer tool wrapper
# fails to stream the output incrementally.
sh -c '
  claude -p --model opus --effort high --output-format json < "$1" > "$2" &
  pid=$!
  echo "$pid" > "$3"
  wait "$pid"
' sh "$BRIEFING_FILE" "$OUTPUT_FILE" "$PID_FILE"

# Read the saved response after the command exits.
cat "$OUTPUT_FILE"
```

`-p` enables non-interactive mode; the briefing file is supplied via stdin,
which avoids shell quoting issues and argument length limits entirely. Do not
use heredocs for briefings or follow-ups. Use quoted one-line arguments for
short prompts, and temporary files for anything longer or more structured.

The JSON response will include a `session_id` field. Record Claude's JSON
`session_id` for follow-up turns. Do not confuse it with any process ID,
session ID, or command handle used by your outer execution environment to
monitor the running shell command. Those are separate concepts:

- The outer execution environment may expose its own process or session handle
  for polling the running command.
- Claude's JSON `session_id` is the one used with `claude -p --resume ...`.

**Claude may take a long time to respond**, especially for large or complex
consultations. Budget up to 15 minutes of wall-clock time for an initial
consultation by default.

If your execution environment exposes a session, process handle, or similar
handle for the running shell command, keep polling that handle while Claude is
running. Poll more frequently during the first minute, then switch to a coarser
poll interval such as 15-30 seconds.

Assume you may see **no live stdout at all** until the process exits. In many
execution environments, Claude will not stream visible output incrementally
even when it is running correctly.

If the process exits successfully but your outer wrapper did not show Claude's
response live, inspect the saved output file before assuming the consultation
failed. The saved output file is the authoritative source of the response.

If the `sh -c` invocation exits non-zero and the saved output file is empty or
unhelpful, inspect any stderr surfaced by your outer execution environment
before retrying. Claude CLI failures may explain themselves only on stderr.

If the 15 minute budget is reached, treat that as a timeout:

1. Read the PID from `"$PID_FILE"`.
2. Send `SIGINT` to request graceful shutdown.
3. Wait a short grace period and see whether the process exits.
4. If it does not exit, send `SIGTERM`.
5. Inform the user that the Claude consultation timed out and proceed without
   it.

A concrete timeout sequence looks like:

```sh
CLAUDE_PID="$(cat "$PID_FILE")"
kill -INT "$CLAUDE_PID" || true
sleep 10
if kill -0 "$CLAUDE_PID" 2>/dev/null; then
  kill -TERM "$CLAUDE_PID" || true
fi
```

If your execution environment lets you terminate the outer running shell
command directly, prefer that over raw PID signaling. The outer execution
environment is usually in the best position to clean up the whole command tree.

Do not leave long-running Claude subprocesses orphaned after a timeout.

### 3. Iterate with follow-ups

For each follow-up turn, resume the session using the `session_id` from the
previous response. Always invoke `claude` from the same working directory used
in step 2 — the session is scoped to that directory, so paths in follow-up
prompts must resolve against that same root:

```
# Even for a short one-line follow-up, still use the recoverable launch form.
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-output.XXXXXX")"
PID_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-pid.XXXXXX")"

sh -c '
  claude -p --model opus --effort high --resume "$1" --output-format json "$2" > "$3" &
  pid=$!
  echo "$pid" > "$4"
  wait "$pid"
' sh "<session_id>" "your follow-up here" "$OUTPUT_FILE" "$PID_FILE"

cat "$OUTPUT_FILE"
```

For longer or more structured follow-ups, use the same temporary file / stdin
technique as the initial call:

```
# Generate unique temporary files using a portable BSD/macOS-safe `mktemp`
# template with trailing Xs.
FOLLOWUP_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-followup.XXXXXX")"
OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-output.XXXXXX")"
PID_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-pid.XXXXXX")"

# Populate "$FOLLOWUP_FILE" with the full follow-up before running Claude.
# Record these exact paths in your own notes or outer execution context before
# launching Claude. You may need them while the command is still running.

# Run `claude` in the same working directory as used in the initial command.
# Capture stdout to a file and record the process PID for timeout handling.
sh -c '
  claude -p --model opus --effort high --resume "$1" --output-format json < "$2" > "$3" &
  pid=$!
  echo "$pid" > "$4"
  wait "$pid"
' sh "<session_id>" "$FOLLOWUP_FILE" "$OUTPUT_FILE" "$PID_FILE"

# Read the saved response after the command exits.
cat "$OUTPUT_FILE"
```

Because Claude retains the full prior exchange in the resumed session, follow-up
prompts do not need to repeat the briefing. Keep them specific and concrete.

Apply the same waiting, polling, recovery, and timeout rules to follow-ups that
you apply to the initial consultation. By default, budget up to 15 minutes of
wall-clock time for a follow-up as well unless you have a specific reason to
use a shorter timeout.

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
- Always pass `--model opus --effort high` to every `claude` invocation,
  both initial and follow-up. Consultations warrant the best model and
  thinking level available.
- Always use `--output-format json` so you can capture the `session_id` for
  session resumption.
- Always use quoted one-line arguments only for short prompts. For anything
  longer or more structured, write the prompt to a temporary file and supply it
  via stdin. Do not use heredocs.
- Always use portable `mktemp` templates with trailing `X`s. Do not use
  examples like `foo.XXXXXX.md`, which are not portable to BSD/macOS
  `mktemp`.
- Always include the anti-circular-consultation instruction at the end of the
  initial briefing. Claude has access to its own tool set, so the prompt
  instruction is the primary guard against invoking `consult-codex`.
- Always instruct Claude (via the prompt) not to modify files.
- Always construct a comprehensive briefing for the initial prompt. Claude's
  consulting session has no access to your conversation history.
- Keep consultations focused on specific, concrete questions. Vague prompts
  produce vague feedback.
- Always launch Claude in a recoverable and cancellable form: save stdout to an
  output file and save the subprocess PID so that you can recover the response
  even if live stdout is not surfaced and can terminate the subprocess if it
  exceeds the timeout.
- Always preserve and inspect the saved output file before deciding that a
  consultation failed. A lack of streamed stdout is not, by itself, evidence
  that Claude did not respond.
- If the Claude launch exits non-zero and the saved output file is empty or
  unhelpful, inspect stderr from the outer execution environment before
  retrying.
- Always distinguish Claude's JSON `session_id` from any process or session
  identifier used by your outer execution environment.
- Allow up to 15 minutes of wall-clock time for a Claude consultation by
  default. If that budget is exceeded, terminate the subprocess cleanly and
  tell the user that the consultation timed out.
- Always clean up temporary briefing, output, and PID files after the
  consultation completes or is abandoned and you no longer need them.
- Escalate to the user if consensus cannot be reached within 4 turns.
