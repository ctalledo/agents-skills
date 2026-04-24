# Sitrep Procedure

Check all notification sources, correlate findings with
existing worklog threads, update the worklog, and present
a situational report.

The worklog repository is at `${HOME}/work-local/ctalledo/worklog/`. The `wl` CLI tool is at `$WORKLOG_PATH/tools/wl`, where `$WORKLOG_PATH`
is an environment variable. At the start of every session, resolve it
once by running `printenv WORKLOG_PATH`. If the output is empty,
stop immediately and report: "Error: WORKLOG_PATH is not set." Use the
resolved absolute path (e.g. `/home/user/worklog/tools/wl`) for all
subsequent `wl` invocations — never re-expand `$WORKLOG_PATH` inline
in commands. Procedure documents
for each notification source are in `~/.claude-procedures/`. All source checks
must return the shared structured format described in
`~/.claude-procedures/findings-schema.md`. Don't ask permission to read or
execute any of these.

The command examples and subagent structure below are recommended starting
points, not a fixed recipe. Adapt the parallelization, batching, and query
strategies to the volume and shape of the data you encounter.

## 1. Pick up the current state

Establish context before checking sources:

```
wl thread list
wl worktree gc
wl scan prune
wl summary commits --since "2 days ago" --oneline
```

If `WORKLOG_PATH` was not set (detected at session start) or the `wl`
binary is not found at the resolved path, report the problem and stop. If the worklog repository is missing or
uninitialized, report the problem and stop.

Check for uncommitted worklog changes from an interrupted
session:

```
git -C <worklog-path> status --porcelain
```

If uncommitted changes are found, they likely represent an
interrupted previous session. Present the dirty paths to the
user and ask whether to commit them with a recovery message
(e.g., `worklog: recover interrupted session`) or to discard
them with `git -C <worklog-path> checkout -- .` before
proceeding. Do not silently proceed with dirty state.

Present a brief summary of active threads and recent
activity before proceeding.

## 2. Check notification sources

Launch forked subagents to check each notification source.
Each subagent follows the corresponding procedure document
in `~/.claude-procedures/` and returns structured findings.

These source-check subagents are **read-only**. They may
read worklog state and query external systems, but they must
not mutate the worklog, advance cursors or checkpoints,
commit, or clean up notifications. The parent sitrep agent
is the **single writer**.

Each subagent needs access to the `wl` tool (for reading
cursors and checkpoints), the relevant CLI tools or MCP
servers, and `config/sources.yaml` (for channel lists,
teams, user IDs, and query patterns).

Recommended subagent structure (launch in parallel where
possible):

1. **GitHub** — follow `check-github.md`. Uses `gh` CLI.
2. **Email** — follow `check-email.md`. Uses `gws` CLI.
3. **Slack (mcp tier)** — follow `check-slack.md`, scoped
   to `mcp` channels (Steps 1, 5, and 6 — skip
   Steps 2–4).
4. **Slack (ai tier)** — same procedure, scoped to `ai`
   channels (Steps 1, 5, and 6).
5. **Slack (general tier)** — same procedure, scoped to
   `general` channels (Steps 1, 5, and 6).
6. **Slack DMs and @-mentions** — follow Steps 2, 5, and 6
   in `check-slack.md`. Note that
   `slack_search_public_and_private` may require an explicit
   consent prompt, especially for DMs and private-channel
   search.
7. **Slack watched threads** — follow Steps 3, 5, and 6 in
   `check-slack.md`. This subagent runs
   `wl thread watched-slack --json` to discover all active
   watched threads and polls them regardless of which
   channel tier they belong to. This avoids duplicate polls
   across the tier-scoped subagents.
8. **Linear** — follow `check-linear.md`. Uses Linear MCP.
9. **Jira** — follow `check-jira.md`. Uses Atlassian MCP.

If a subagent fails, log the failure and continue with the
remaining sources. Report the failure in the final sitrep so
the user is aware. Do not let one source failure block the
entire report.

## 3. Correlate findings

Once subagents have returned, correlate findings across
sources:

1. **Deduplicate.** A GitHub notification email and a GitHub
   API notification for the same PR are the same event.
   Match by PR/issue number and repository.

2. **Match to existing threads.** For each finding, search
   the worklog:
   ```
   wl thread find --source "github:docker/mcp-gateway#1234"
   ```
   If a match exists, classify the finding as an update to
   that thread.

3. **Detect completions.** If a finding indicates a PR was
   merged, an issue was resolved, or a task was completed,
   and there is a corresponding active worklog thread, mark
   it for completion. Also proactively check the state of
   PRs associated with existing `pr-review` threads:
   ```
   gh pr view <number> -R <repo> --json state --jq '.state'
   ```
   If the PR is `MERGED` or `CLOSED`, propose completing
   the thread regardless of whether a notification was
   received about it.

4. **Filter review requests.** Before creating a
   `pr-review` thread for a review request, verify the
   review was requested of Cesar directly (per
   `github.user` in `config/sources.yaml`) or of one of the
   monitored `github.teams` objects. Cesar belongs to many
   large organizational teams that generate non-actionable
   review requests. If in doubt, check the PR's requested
   reviewers:
   ```
   gh pr view <number> -R <repo> \
       --json reviewRequests \
       --jq '[.reviewRequests[].login // .reviewRequests[].name]'
   ```
   If no match, discard the finding — do not create a
   thread.

5. **Filter draft PRs.** Before creating a `pr-review`
   thread, check if the PR is a draft:
   ```
   gh pr view <number> -R <repo> --json isDraft --jq '.isDraft'
   ```
   Do not create threads for draft PRs — they are not yet
   ready for review. If a draft PR later becomes ready for
   review, it will be picked up in a subsequent sitrep cycle
   via a new `review_requested` notification.

6. **Filter merged/closed PRs.** Before creating a
   `pr-review` thread, verify the PR is still open:
   ```
   gh pr view <number> -R <repo> --json state --jq '.state'
   ```
   If the PR is `MERGED` or `CLOSED`, do not create a
   thread. Classify it as a completion (if there is an
   existing thread to close) or discard it.

7. **Search before creating.** For findings that do not
   match an existing thread, also search by keyword before
   creating:
   ```
   wl thread search "<relevant keywords>"
   ```
   **One PR per thread.** Each `pr-review` thread must
   correspond to exactly one PR. Never group multiple PRs
   into a single thread, even if they share a repository or
   author.

8. **Classify priority.** Use the rules in
   `config/preferences.yaml` to assign priority to new
   threads and flag overdue items (e.g., PRs awaiting review
   for longer than `thresholds.pr_review_overdue_hours`).

9. **Collect proposed state updates.** Merge the proposed
   checkpoint and cursor values from the structured
   findings. For checkpoints, use the subagent's recorded
   `scan_started_at` value, not the wall-clock time at
   correlation or apply time.

## 4. Propose worklog changes

Build a changeset of proposed modifications:

- New threads to create (with title, type, priority,
  sources, tags).
- Thread updates (status changes, new source refs, activity
  log entries).
- Thread completions (threads to move to completed).
- Cursor updates (Slack channel cursors to advance).
- Checkpoint updates (source checkpoint timestamps).
- Source-check failures and consent-skipped scopes.

Present the changeset to the user for approval before making
any changes. Use a clear, scannable format — group by new
threads, updates, completions, and notification cleanup.
Include the list of emails to be trashed with their subject
lines so the user can review before confirming.

Do not apply any changes until the user approves.

## 5. Apply changes

After user approval:

**5a. Apply worklog changes** using `wl thread create`,
`wl thread update`, `wl thread complete`,
`wl state cursor set`, and `wl state checkpoint set` as
appropriate. If any `wl` command fails, report the error and
continue with the remaining operations.

Only the parent sitrep agent applies these mutations.
Subagents never mutate the worklog directly.

**5b. Commit the worklog.** Stage only the paths that were
modified during this sitrep cycle, then commit with
sign-off:
```
git -C <worklog-path> add <modified-paths...>
git -C <worklog-path> commit -s -m "worklog: sitrep check — <summary>"
```
Replace `<modified-paths...>` with the specific files or
directories that changed (e.g., `threads/ state/
sitreps/scans/`). Include `sitreps/scans/` whenever any
source-check subagent returned a `scan_log_path`. Do not
use broad staging commands such as `git add -A` or
`git add .`.

**5b (troubleshooting).** If a subagent returns
`status: partial` or `status: failed`, check its
`scan_log_path` for unchecked `- [ ]` items. Any item
left unchecked indicates enumeration or classification was
incomplete. The scan log shows exactly which items were
fetched and which were processed, making it straightforward
to resume or re-run only the affected portion of the
check.

If the commit fails, do NOT proceed with notification
cleanup. Report the failure and stop.

**5c. Clean up notifications (only after commit).**

Collect all cleanup identifiers from **every** source-check
subagent's findings. Cleanup lists may contain identifiers
for items that have no corresponding finding (e.g., emails
from ignored authors that were inspected but not classified).
Process all of them — do not skip cleanup entries just
because they lack a matching finding.

Present the email cleanup list to the user one more time for
final confirmation. After the user confirms:

- **Email**: iterate over `cleanup.email_message_ids` from
  the email subagent's findings. For each message ID, mark
  the Gmail message as read, then trash it (use
  `gws gmail users messages modify` and
  `gws gmail users messages trash`). Only messages seen
  during the scan are trashed; any new messages arriving in
  the same thread after the scan started remain in the
  inbox and will be picked up in the next sitrep cycle.
  Always trash — never permanently delete.
- **GitHub**: iterate over
  `cleanup.github_notification_ids` from the GitHub
  subagent's findings. Mark each notification as read
  (`gh api /notifications/threads/<ID> --method PATCH`).
- Linear and Jira notifications are marked as read by their
  platforms when viewed. No explicit action is needed.
- Slack messages are not marked as read — the user manages
  this manually.

## 6. Present the sitrep

After all changes are applied, present the final situational
report.

### Link formatting

All items in the sitrep must include clickable links to
their source. Use **bare URLs** on their own line below each
item — do not use Markdown link syntax like `[text](url)`
because it does not render as clickable in terminal
environments. Bare URLs are auto-detected and made clickable
by most terminals.

Link formats by source:

- **GitHub**:
  `https://github.com/<owner>/<repo>/pull/<number>` or
  `.../issues/<number>`
- **Slack message**:
  `https://docker.slack.com/archives/<CHANNEL_ID>/p<TS>`
  where `<TS>` is the message timestamp with the dot removed
  (e.g., timestamp `1773139486.111619` becomes
  `p1773139486111619`).
- **Slack thread reply**: append
  `?thread_ts=<PARENT_TS>&cid=<CHANNEL_ID>` where
  `<PARENT_TS>` keeps the dot.
- **Jira**:
  `https://docker.atlassian.net/browse/<ISSUE_KEY>`
- **Linear**:
  `https://linear.app/docker/issue/<ISSUE_ID>`

Include links in every section: action items, status
updates, and the suggested plan of action. When an item has
multiple sources, include all links.

### Report structure

Organize the report with these sections:

- **Summary**: counts of active threads,
  new/updated/completed this check.
- **Action items (by priority)**: grouped into Critical,
  High, Medium, Low. Each item shows thread ID, type,
  title, and bare source link(s).
- **Status updates**: FYI items that do not require action.
- **Completed**: threads closed this check.
- **Suggested plan of action**: a prioritized, ordered
  recommendation of what to work on. The plan is a
  recommendation — the user decides the actual order.

## Tips

- If the volume of findings is high, present them in batches
  rather than one overwhelming changeset. Start with
  action-required items.
- When correlating, err on the side of creating a new thread
  rather than incorrectly updating an unrelated one. The
  user can merge duplicates later.
- The Slack checks are split by priority tier so that
  high-priority channels complete and display first, even if
  lower-priority channels are still loading.
- Keep source-check subagents forked so their potentially
  large responses do not pollute the main context window.
- If a checkpoint is stale (e.g., after a vacation), expect
  higher volumes. Use pagination and time-scoped queries to
  avoid overwhelming any single subagent.

## Constraints

- Do not apply worklog changes or clean up notifications
  without explicit user approval. Probing and analysis are
  unrestricted.
- Source-check subagents are read-only and must return
  structured findings via the shared findings schema.
- Always commit worklog changes before cleaning up
  notifications. This is a hard invariant — if the commit
  fails, stop.
- Always advance checkpoints to the source check's recorded
  `scan_started_at`, not to a later wall-clock time. This
  prevents gaps during long scans.
- Email cleanup uses Gmail message IDs (not thread IDs) and
  moves to Trash (not permanent delete). Only messages seen
  during the scan are trashed. The 30-day Trash retention
  is a safety net.
- Always search for existing threads before creating new
  ones (`wl thread find` and `wl thread search`). This
  prevents duplicates.
- One PR per thread. Never batch multiple PRs into a single
  thread.
- Never pre-compute Unix or Slack timestamps when writing
  subagent prompts. Pass ISO checkpoint values as strings
  and instruct subagents to convert them using
  `wl util iso-to-unix` or `wl util iso-to-slack`. Manual
  timestamp arithmetic is error-prone (e.g. off-by-one-year
  bugs) and bypasses the wl tooling that exists for this
  purpose.
- Never merge PRs. Never propose or suggest merging PRs.
  Merging is only performed when Cesar explicitly requests
  it in a separate instruction. This applies to all
  workflows that build on the sitrep, including the
  concierge.
