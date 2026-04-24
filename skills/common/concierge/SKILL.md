---
name: concierge
description: >-
  Start or resume the concierge workflow. Runs a situational report across all
  notification sources, then interactively steps through action items with
  Cesar. This is the primary entry point for daily workflow automation.
disable-model-invocation: true
argument-hint: "[resume]"
compatibility: >-
  Requires gh CLI, gws CLI, Slack MCP, Linear MCP, Atlassian MCP, and the wl
  tool in the worklog repository. Uses review-pr, drive-pr, fix-ci,
  consult-codex, read-doc, and worklog-report skills.
---

# Concierge

Cesar's daily workflow orchestrator. Checks notification sources, correlates
findings into the worklog, presents a situational report, and then
interactively works through action items.

The worklog repository is at `worklog/` relative to the
directory where Claude was invoked. The `wl` CLI tool is at `$WORKLOG_PATH/tools/wl`, where
`$WORKLOG_PATH` is an environment variable. At the start,
resolve it once by running `printenv WORKLOG_PATH`. If the
output is empty, stop immediately and report:
"Error: WORKLOG_PATH is not set." Use the resolved absolute
path for all subsequent `wl` invocations — never
re-expand `$WORKLOG_PATH` inline in commands.
Procedure documents for source checks are in
`~/.claude-procedures/`. Source-check subagents must use the
shared findings schema and remain read-only; the concierge
parent agent is the single writer.

Available skills for dispatching work:
- `review-pr` — Review a PR.
- `drive-pr` — Drive a PR toward completion.
- `fix-ci` — Diagnose and fix failing CI.
- `consult-codex` — Cross-check work with Codex.
- `read-doc` — Read a Google Doc.
- `worklog-report` — Generate a report.

The work plan and action strategies below are recommended starting points, not
a fixed recipe. Every day looks different — adapt to the shape of the work and
Cesar's priorities.

## Modes

### Fresh start (`/concierge`)

Run the full flow from Step 1 (Sitrep) through Step 3 (Work).

### Resume (`/concierge resume`)

Skip the sitrep and go directly to Step 2 (Plan) using the existing worklog
state. Use this when:
- A previous concierge session was interrupted.
- Cesar already ran `/sitrep` separately.
- Cesar wants to continue working through items from an earlier session.

## Procedure

### 1. Sitrep

Run the full sitrep procedure in `~/.claude-procedures/sitrep.md`. This includes
checking all notification sources, correlating findings, proposing worklog
changes for approval, committing, cleaning up notifications, and presenting
the situational report.

If the sitrep includes Slack DM or private-channel search, be prepared for an
MCP consent prompt because `slack_search_public_and_private` may require it.

In resume mode, skip the sitrep and read the current worklog state instead:

```
wl thread list
wl summary stats
wl worktree gc
```

Check for uncommitted worklog changes from an interrupted session:

```
git -C <worklog-path> status --porcelain
```

If uncommitted changes are found, they likely represent an interrupted previous
session. Present the dirty paths to the user and ask whether to commit them
with a recovery message (e.g., `worklog: recover interrupted session`) or to
discard them with `git -C <worklog-path> checkout -- .` before proceeding. Do
not silently proceed with dirty state.

If the worklog has no active threads (e.g., fresh start with no prior sitrep),
suggest running `/sitrep` first.

### 2. Plan

After the sitrep (or state pickup), present a plan of action. Organize items
by priority and estimated effort. Include the thread ID, type, priority, a
brief description, and the recommended skill or approach.

Suggested groupings:

- **Quick wins** (< 10 min): Slack replies, comment responses, status checks.
- **PR reviews** (15–30 min): Pending reviews using `review-pr`.
- **Own PR management**: Feedback to address, CI fixes using `drive-pr`
  and `fix-ci`.
- **Development work** (30+ min): Implementation, design, research.
- **Items needing input**: Docs to read, decisions to make.
- **Deferred / monitoring**: Items with no immediate action.

After presenting the plan, wait for Cesar to review and adjust. He may reorder,
skip, add, or change the approach for items. He may also request that
independent items be handled in parallel.

### 3. Work

Step through the approved plan item by item.

#### 3a. Announce each item

Before starting an item, announce it clearly with its thread ID, type, priority,
and planned approach.

#### 3b. Execute the approach

Adapt the execution strategy to the item type. Common patterns:

**PR reviews** — Invoke `review-pr`. Multiple independent reviews can be
parallelized if Cesar approves. The concierge parent creates and records the
worktree, dispatches the shared skill inside that worktree, and then cleans up
the worktree afterward. Results are presented for approval before posting.

**Driving own PRs** — Invoke `drive-pr` interactively in the main conversation.
Unlike PR reviews (which run as autonomous subagents), drive-pr requires
interactive approval at each step and runs inline. For CI failures, `drive-pr`
will delegate to `fix-ci` as needed. If the work requires a local checkout, the
concierge parent sets up a worktree beforehand and cleans it up afterward. All
code changes and comment replies require Cesar's approval before any visible
action.

**Reading docs** — Invoke `read-doc` to fetch the content. Summarize key
points. Help Cesar formulate feedback or a response.

**Composing replies** (Slack, GitHub, etc.) — Draft the reply, present it for
approval, then post via the appropriate tool.

**Interactive development** — Discuss the approach, plan the implementation,
write code interactively with Cesar reviewing each step. Cross-check with
`consult-codex` at key milestones. This is the most hands-on mode — the
concierge acts as a pair programming partner.

**Consulting Codex** — For any item where a second opinion is valuable, invoke
`consult-codex`. Present the synthesized analysis.

#### 3c. Update the worklog

After each item is handled (or partially handled):

```
wl thread update <id> --status <new-status> \
    --add-log "Concierge: <summary of work done>."
```

Commit after each item or after a batch of related items:

Stage only the paths that were modified, then commit with
sign-off:
```
git -C <worklog-path> add <modified-paths...>
git -C <worklog-path> commit -s -m "worklog: update <id> — <summary>"
```
Replace `<modified-paths...>` with the specific files or
directories that changed. Do not use broad staging commands
such as `git add -A` or `git add .`.

If a `wl` command or commit fails, report the error but continue with the
session.

#### 3d. Transition to the next item

After completing or deferring an item, present a brief status update and ask
before starting the next item. Cesar may want to adjust the remaining plan,
take a break, switch to something off-plan, or end the session.

### 4. Parallelization

When Cesar approves parallel work, launch multiple subagents simultaneously.
Good candidates:

- **Multiple PR reviews**: Each in its own parent-managed worktree.
- **Codex cross-checks**: Can run in the background while Claude does other
  analysis.

Present parallel results as they complete. If one finishes before others,
present it to Cesar while waiting.

### 5. Session wrap-up

When Cesar wants to end the session or all items are handled:

1. Present a session summary: items completed, deferred, still active, and
   any new items discovered during the session.
2. Offer to generate a standup report via `worklog-report`.
3. Ensure all worklog changes are committed.
4. Clean up stale worktrees: `wl worktree gc`.

## Tips

- Keep context lean. Use `wl` tool commands for compact data access and forked
  subagents for source checks so their large responses do not pollute the main
  conversation.
- Cross-check generously. Use `consult-codex` for any work product that will
  be visible to others — PR reviews, code changes, design feedback.
- Commit frequently. Small, descriptive commits after each meaningful action
  ensure continuity across sessions.
- Track worktrees. The concierge parent must record worktrees via
  `wl worktree add`, pass the path into the delegated skill, and remove the
  tracking entry after cleanup. Run `wl worktree gc` at session start and end.
- The plan is a starting point, not a rigid script. Expect Cesar to redirect
  at any time.

## Constraints

- **Always confirm before acting.** The concierge proposes, Cesar decides.
  Never post reviews, push code, send messages, or take any externally
  visible action without explicit approval.
- **Never merge PRs.** Do not merge PRs and do not propose or suggest
  merging. Merging is only performed when Cesar explicitly requests it
  in a separate instruction. The concierge reviews, tracks, and approves
  — merging is Cesar's decision to initiate.
- **All GitHub interaction goes through the `gh` CLI.** All Slack, Linear,
  and Jira interaction goes through their respective MCP servers.
- **Worklog commits before notification cleanup.** If a commit fails, do not
  clean up notifications.
- **One PR per thread.** Never batch multiple PRs into a single worklog thread.
- **Source checks are read-only.** Cursor and checkpoint updates are proposed
  during sitrep correlation, then applied only by the parent agent after
  approval.
- **Probing and analysis are unrestricted.** Reading code, checking status,
  running `wl` queries, and preparing drafts do not require permission.
  Mutations and externally visible actions do.

## Error recovery

If the session is interrupted at any point, the worklog is the source of truth.
All committed changes are preserved. A new `/concierge resume` session can pick
up where things left off.

If a subagent fails (e.g., a PR review subagent crashes), report the failure,
log it in the worklog thread, and continue with other items. Do not let one
failure block the session.

## Target

$ARGUMENTS
