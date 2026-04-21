# Worklog Procedure

> **Canonical reference:** `worklog/CLAUDE.md` is the
> authoritative source for the `wl` tool's command
> inventory, thread format, and commit conventions. This
> document covers operational patterns and subagent-relevant
> context that complement CLAUDE.md.

This document describes how to manage work threads, cursors,
checkpoints, and worktrees in Jacob's worklog repository
using the `wl` CLI tool. This procedure is used by the
sitrep and concierge skills.

The `wl` tool is at `worklog/tools/wl` relative to the
Docker workspace root. The worklog repository is at
`worklog/`.

## Core Invariants

1. **Search before create.** Always search both active and
   completed threads (`wl thread find --source <ref>` and
   `wl thread search <query>`) before creating a new thread.
   This prevents duplicates and detects resumptions of
   previously completed work.

2. **Commit before cleanup.** Always commit worklog changes
   to Git before marking notifications as read, trashing
   emails, or performing any other irreversible cleanup. If
   the session is interrupted between commit and cleanup,
   the worst case is re-processing already-recorded
   notifications — not data loss.

3. **Log everything.** Every significant action should be
   recorded as an activity log entry on the relevant thread
   via `wl thread update <id> --add-log "description"`.

4. **Single writer.** Source-check subagents are read-only.
   They return proposed thread/state changes in the shared
   findings schema. The parent agent is the only writer that
   applies `wl` mutations after Jacob approves the
   changeset.

5. **Slack-source threads are watched.** Any active worklog
   thread that contains a Slack source implicitly watches
   that Slack thread until the worklog thread is completed.
   The parent/root Slack thread is watched, not just a
   single reply.

## Cursor Management

Slack cursors track the last-read message timestamp for each
monitored cursor key. Most keys are channel IDs. The
special `mentions` key tracks DM / @-mention searches.
Watched Slack threads use keys of the form
`watch-slack:<channel-id>/<thread-ts>`.

```bash
# Get the last cursor for a channel.
wl state cursor get C08J27QSJJJ

# Get the DM / @-mention search cursor.
wl state cursor get mentions

# Set a new cursor after approval and apply.
wl state cursor set C08J27QSJJJ "1741234567.123456"

# List all cursors.
wl state cursor list
```

### Cursor Update Pattern

When checking a Slack channel:

1. Read the current cursor:
   `wl state cursor get <channel-id>`
2. Use the Slack MCP `slack_read_channel` tool to fetch
   messages newer than the cursor timestamp.
3. Record the **proposed** new cursor value in the findings
   schema.
4. After Jacob approves the changeset, the parent agent
   applies it:
   `wl state cursor set <channel-id> <newest-ts>`

If no new messages were found, still propose the existing
cursor value so the parent can refresh `last_check`.

### Watched Slack Threads

Active worklog threads with Slack sources are implicitly
watched until completion. The canonical watch root is:

- The parent thread timestamp when the source ref is a
  Slack thread reply.
- The message timestamp itself when the source ref is a
  standalone message or thread parent.

Use the helper command to enumerate these watches:

```bash
wl thread watched-slack --json
```

For each returned object:

1. Read the existing watch cursor:
   `wl state cursor get <cursor_key>`
2. If it is empty, start from `default_oldest_ts`.
3. Read the Slack thread with `slack_read_thread`.
4. Return a proposed cursor update for the same
   `cursor_key`.

Watch cursors may remain in `cursors.yaml` after the owning
work item completes. This is harmless; if no active work
thread references the Slack source, the watch will no longer
be polled.

## Checkpoint Management

Checkpoints track the last-checked timestamp for each
notification source (github, email, linear, jira).

```bash
# Get the last checkpoint.
wl state checkpoint get github

# Convert a checkpoint for Slack or Jira queries.
wl util iso-to-slack "2026-03-12T15:00:00Z"
wl util iso-to-jql "2026-03-12T15:00:00Z"

# Set after approval and apply.
wl state checkpoint set github "2026-03-12T15:00:00Z"
```

### Checkpoint Update Pattern

When checking a source:

1. Read the current checkpoint:
   `wl state checkpoint get <source>`
2. Capture the scan start time **before** issuing any source
   query:
   `scan_started_at="$(wl util now --format iso)"`
3. Query the source for notifications since the prior
   checkpoint.
4. Process the findings and return
   `proposed_state_updates.checkpoint = scan_started_at`.
5. After Jacob approves the changeset and the worklog
   mutations succeed, apply the checkpoint:
   `wl state checkpoint set <source> "$scan_started_at"`

## Worktree Tracking

Track Git worktrees created by subagents for PR review or
development tasks.

```bash
# Record a new worktree.
wl worktree add /path/to/worktree 0000001

# List tracked worktrees.
wl worktree list

# Remove a record after cleanup.
wl worktree remove /path/to/worktree

# Clean up records for worktrees that no longer exist.
wl worktree gc
```

### Worktree Lifecycle

1. When a subagent creates a worktree, record it:
   `wl worktree add <path> <thread-id>`
2. The parent agent owns this lifecycle, even when the
   substantive work is delegated to a shared skill that is
   unaware of the worklog.
3. When the subagent completes and the worktree is no longer
   needed, clean up the worktree directory with
   `git worktree remove <path>`, then untrack it:
   `wl worktree remove <path>`
4. Periodically (e.g. at the start of a concierge session),
   run `wl worktree gc` to prune stale entries.

## Weekend-Aware SLA Checks

When evaluating review overdue-ness or similar reminders,
do not use raw wall-clock elapsed hours if weekends should
be ignored. Read `business_time` from
`config/preferences.yaml` and use:

```bash
wl util add-weekday-hours <start-iso-ts> <hours>
```

This computes the due timestamp in the configured business
timezone while skipping Saturday and Sunday entirely.

## Git Commit Conventions

After making worklog changes, commit them to the worklog
repository. Run all git commands with `-C` to target the
worklog repo without changing the working directory:

```bash
git -C <worklog-path> add <modified-paths...>
git -C <worklog-path> commit -s -m "worklog: <action> — <summary>

- Detail 1.
- Detail 2."
```

Replace `<modified-paths...>` with the specific files or
directories that changed. Do not use broad staging commands
such as `git add -A` or `git add .`.

### Commit Message Format

```
worklog: <action> — <summary>

- Detail 1.
- Detail 2.
```

Actions: `sitrep check`, `create NNNNNNN`,
`update NNNNNNN`, `complete NNNNNNN`, `revive NNNNNNN`,
`cleanup`, `report`.

### When to Commit

- After a sitrep check cycle (batch all changes from the
  cycle into one commit).
- After updating a work item during the WORK phase.
- After completing or reviving a thread.
- After generating a report.

Multiple changes can be batched into a single commit. The
commit message should summarize all changes.

## Tips

- Prefer `wl thread list` and `wl thread meta` over
  `wl thread get` for routine lookups — they keep context
  lean by omitting the full activity log and body.
- Batch multiple `wl` mutations before committing rather
  than committing after every single change.
- When the `wl` tool reports an error, check whether the
  thread ID exists with `wl thread meta <id>` before
  retrying with different arguments.
- Run `wl worktree gc` at the start and end of every
  concierge session to catch stale worktrees early.

## Constraints

- Worklog changes require user approval before committing
  (enforced by the sitrep and concierge skills, not by
  `wl` itself).
- Always commit before cleaning up notifications. If the
  commit fails, do not proceed with cleanup.
- Always search before creating (`wl thread find` and
  `wl thread search`). This is a hard invariant.
- Git commands targeting the worklog repo should use
  `git -C <worklog-path>` to avoid changing the shell's
  working directory.
- Stage only the specific paths that were modified. Do not
  use `git add -A` or `git add .`. Use `git commit -s` to
  include a sign-off line on all worklog commits.
