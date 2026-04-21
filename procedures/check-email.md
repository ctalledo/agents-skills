# Check Email Procedure

This procedure checks Gmail for development-related email
notifications (GitHub notifications and Google Workspace
notifications). It is run as a forked subagent by the
sitrep and concierge skills.

Cesar has read/write access to Gmail via the `gws` CLI
tool.

The command examples below are recommended starting points.
Adapt queries and field selections to the volume of mail
and the current task.

## Configuration

Read the email query patterns from `config/sources.yaml`:

```yaml
email:
  github_query: "from:notifications@github.com"
  google_workspace_query: "from:*-noreply@docs.google.com"
```

Read the last checkpoint and capture the scan start time:

```bash
wl state checkpoint get email
scan_started_at="$(wl util now --format iso)"
```

If the checkpoint is empty (first run), use `newer_than:1d`
as a reasonable default. Otherwise, convert the checkpoint
to Unix seconds:

```bash
checkpoint_unix="$(wl util iso-to-unix "$checkpoint")"
```

## Before Step 1: Initialize the Scan Log

Create the scan log file before issuing any API queries:

```bash
scan_log="$(wl scan init email)"
```

This returns the absolute path to the scan log file (e.g.,
`worklog/sitreps/scans/2026-03-19T143645Z-email.md`).
Record this path — it will be returned in the findings.

All item enumeration (Phase 1) and classification
(Phase 2) results are written to this file. Its frontmatter
tracks pagination progress and phase completion flags.
If the subagent crashes mid-run, any unchecked `- [ ]`
items in the file are visibly unprocessed.

## Phase 1: Enumerate Messages

The goal of Phase 1 is to enumerate **all** message IDs
to the scan log before classifying any of them. Do not
retain individual items in memory across pages — the scan
log is the record.

### Step 1: List GitHub Notification Emails

Search for unread GitHub notification emails:

```bash
gws gmail users messages list \
    --params '{
        "userId": "me",
        "q": "from:notifications@github.com is:unread after:<CHECKPOINT_UNIX>"
    }'
```

If the checkpoint is empty, use the fallback query:

```bash
gws gmail users messages list \
    --params '{
        "userId": "me",
        "q": "from:notifications@github.com is:unread newer_than:1d"
    }'
```

Keep `is:unread` in the query as a safety net, but the
checkpoint is the primary lower bound.

#### Pagination — MANDATORY, do not skip

**You must paginate through every page before classifying
any message.** Gmail returns at most 100 results per page
and results are ordered newest-first. Stopping after the
first page silently discards older messages in the same
window — they will not be caught by the next sitrep
because the checkpoint will have advanced past them.

After each page:
1. Append each message ID to the scan log as an unchecked
   `- [ ]` line under `## Items`:
   ```
   - [ ] `msg:<ID>` `thread:<THREAD_ID>` — (pending)
   ```
2. Record the page in the `## Pagination Log` section:
   ```
   - Page N: M items (token: <PREV> → <NEXT>).
   ```
3. Do **not** retain the full list in context.
4. If the response contains a `nextPageToken` field,
   fetch the next page immediately before doing anything
   else:
   ```bash
   gws gmail users messages list \
       --params '{
           "userId": "me",
           "q": "from:notifications@github.com is:unread after:<CHECKPOINT_UNIX>",
           "pageToken": "<NEXT_PAGE_TOKEN>"
       }'
   ```
5. Repeat until a page contains no `nextPageToken`.

**Do not begin Phase 2 classification until all pages are
exhausted and `phase1_complete: true` is written to the
scan log frontmatter.** If you are unsure whether
pagination is complete, re-read the scan log and count
the `- [ ]` items — they should match
`pagination.total_items`.

After all pages are exhausted, update the frontmatter:

```bash
# Use yq --front-matter=process to update only the
# frontmatter, leaving the Markdown body intact.
yq --front-matter=process \
    '.pagination.pages = N | .pagination.total_items = T | .pagination.phase1_complete = true' \
    -i "$scan_log"
```

Apply the same pagination and append logic to Step 2.

### Step 2: List Google Workspace Notification Emails

Search for unread Google Workspace notifications (doc
comments, share notifications, etc.):

```bash
gws gmail users messages list \
    --params '{
        "userId": "me",
        "q": "from:*-noreply@docs.google.com is:unread after:<CHECKPOINT_UNIX>"
    }'
```

If the checkpoint is empty, use:

```bash
gws gmail users messages list \
    --params '{
        "userId": "me",
        "q": "from:*-noreply@docs.google.com is:unread newer_than:1d"
    }'
```

Append message IDs to the scan log and record pages,
exactly as in Step 1. Update `pagination.total_items`
to the combined GitHub + Workspace count.

## Phase 2: Classify Messages

Phase 2 reads the item list from the scan log and
classifies each message. Process items in batches of
20–30 to avoid context pressure.

### Step 3: Fetch Message Metadata

Read the unchecked `- [ ]` lines from the scan log to
get the message IDs. For each batch, fetch the metadata
(subject, sender, date) without the full body:

```bash
gws gmail users messages get \
    --params '{
        "userId": "me",
        "id": "MESSAGE_ID",
        "format": "metadata",
        "metadataHeaders": [
            "Subject", "From", "Date", "List-ID"
        ]
    }' \
    --fields "id,threadId,snippet,payload.headers"
```

The response includes `id`, `threadId`, `snippet`, and
`payload.headers`. The message `id` is the primary
identifier used for cleanup. The `threadId` is useful for
grouping messages from the same PR or issue during
classification, but is not used in the cleanup list.

If Gmail API rate limits are encountered for a batch,
report the failure for the affected batch and continue
with the messages that succeeded.

After classifying each batch, update the scan log:
- Mark classified items: replace `- [ ]` with `- [x]`
  and append the classification label.
- Example:
  ```
  - [x] `msg:19d034511da8347c` `thread:19d034511da8347c` — Re: [docker/mcp-gateway] PR #293 — **cleanup-only**
  ```

### Filtering Ignored Authors

Before classifying a GitHub notification email, check
whether it was generated by an author listed in
`github.ignored_authors` in `config/sources.yaml`. The
author can often be identified from the email snippet
(e.g., `mcp-registry-bot[bot] left a comment`) or
subject. Bot accounts are listed without the `[bot]`
suffix in the config. If the author matches an ignored
author, do not include it in findings or create a worklog
thread for it. However, **do** include the email's message
ID in the cleanup list and mark the scan log item as
`- [x]` with label `**cleanup-only**`.

### Parsing GitHub Notification Emails

GitHub notification emails contain useful information in
their headers and subjects:

- **Subject**: Contains the PR/issue title and number.
  Example: `Re: [docker/mcp-gateway] Add caching layer
  (#1234)`
- **List-ID**: Contains the repo name. Example:
  `docker/mcp-gateway.docker.com`
- **Snippet**: First ~200 chars of the email body,
  typically contains the comment or action summary.

Extract the following from each GitHub email:
- Repository: from `List-ID` header or subject.
- PR/Issue number: from subject (inside `(#NNN)`).
- Action type: from subject prefix (`Re:` = reply,
  bare = new notification) and snippet content.

### Parsing Google Workspace Emails

Google Workspace notification emails indicate:
- **Doc comments**: Subject contains the doc title and
  commenter name.
- **Share notifications**: Subject indicates who shared
  what.
- **Suggestion notifications**: Subject mentions suggested
  edits.

Extract the document title and any identifiable Google
Doc ID from the email content.

### Step 4: Classify Findings

Organize findings into categories:

#### Action Required

- Review request emails from GitHub — but **only** if the
  review was requested of Cesar directly (per `github.user`
  in `config/sources.yaml`) or of one of the monitored
  team objects under `github.teams` in
  `config/sources.yaml`. GitHub sends review request
  emails for every team the user belongs to, including
  large organizational teams that are not actionable. If
  the email subject or snippet does not indicate who the
  review was requested of, defer to the GitHub check for
  classification — do not assume it is actionable.
- @-mention emails from GitHub.
- Doc comment emails where Cesar is asked a question or
  assigned an action.
- Direct share notifications for new docs.

#### Status Update Only

- GitHub notification emails for threads Cesar is
  subscribed to (no direct action needed).
- Doc comment notifications that are FYI.
- CI notification emails.

#### Non-Development (Skip)

- Marketing emails, HR announcements, calendar
  notifications, and other non-engineering emails should
  be ignored entirely. Do not include them in findings or
  in the cleanup list.

After all items are classified, update the scan log
frontmatter to record final counts and mark Phase 2
complete:

```bash
yq --front-matter=process '
    .status = "ok" |
    .pagination.phase2_complete = true |
    .classified.action_required = A |
    .classified.status_update = S |
    .classified.completed = C |
    .classified.ignored = I |
    .classified.cleanup_only = U
' -i "$scan_log"
```

Use `status: "partial"` if some batches failed.

## Step 5: Return Structured Findings

Return a single YAML block using the shared findings
schema in `findings-schema.md`.

Email-specific requirements:

- Set `source: email`.
- Set `scan_started_at` to the value captured at the start
  of the check.
- Set `scan_log_path` to the worklog-relative path of the
  scan log (strip the worklog directory prefix from the
  absolute path returned by `wl scan init`).
- Put Gmail **message IDs** in `cleanup.email_message_ids`.
  **Include message IDs from ignored authors** (per the
  "Filtering Ignored Authors" section) even though those
  emails do not generate findings. Every development-related
  message that was inspected must have its message ID in
  the cleanup list so the caller can trash it. Only include
  the specific messages seen during this scan — do not
  attempt to enumerate other messages in the same thread.
- Set `proposed_state_updates.checkpoint = scan_started_at`.
- Use `refs` entries such as
  `github:docker/mcp-gateway#1234` or `doc:<document-id>`.

## Email Cleanup Commands

These commands are NOT run by this procedure — they are
run by the sitrep/concierge after worklog commit and after
Cesar confirms the cleanup list.

Cleanup operates on individual Gmail **message IDs** —
only the specific messages seen during the scan are
trashed. Any new messages arriving in the same thread
after the scan started are left in the inbox and will be
picked up in the next sitrep cycle. Mark as read first,
then trash.

```bash
# 1. Mark the message as read.
gws gmail users messages modify \
    --params '{"userId": "me", "id": "MESSAGE_ID"}' \
    --json '{"removeLabelIds": ["UNREAD"]}'

# 2. Trash the message (auto-deleted after 30 days).
gws gmail users messages trash \
    --params '{"userId": "me", "id": "MESSAGE_ID"}'
```

**Critical:** The `gws` CLI only accepts `--params` JSON
form. Positional arguments and shorthand flags (e.g.,
`gws gmail users messages trash me --id "..."`) are not
supported and will return an error. Do not suppress
errors with `>/dev/null 2>&1` — always let cleanup
failures surface so they can be caught and retried.

After processing all message IDs, verify the inbox is
clear by re-running the bounded inbox query (using
`in:inbox after:<PREV_CHECKPOINT> before:<CURR_CHECKPOINT>`)
and confirming zero results. If any messages remain,
retry the failed IDs.

Important: always move to Trash, never permanently delete.
The 30-day Trash retention provides a safety net.

## Tips

- Always use `--fields` with `gws` commands to minimize
  the response size. Full email bodies can be enormous.
- Use `format: "metadata"` when fetching messages to avoid
  loading the full body — the subject, snippet, and headers
  are usually sufficient for classification.
- If a `gws` command fails (network error, auth issue),
  report the failure and continue with other email
  categories rather than stopping entirely.
- Non-development emails should be silently skipped — do
  not add them to the cleanup list or findings.
- When in doubt about whether a review request email is
  actionable, defer to the GitHub check for classification
  rather than guessing.
- The scan log is the durable record of what was fetched.
  After each pagination page, append to the log before
  continuing. If the subagent is interrupted, the log shows
  exactly which items were enumerated and which were
  classified.

## Constraints

- This procedure is read-only. It reads and classifies but
  does not trash email, mark it read, or update the email
  checkpoint directly. The caller handles cleanup and state
  updates after worklog commit and approval.
- Cleanup uses Gmail **message IDs** (not thread IDs) and
  moves to Trash (not permanent delete). Only messages seen
  during the scan are included in the cleanup list.
- The canonical worklog source ref format for GitHub is
  `github:<owner>/<repo>#<number>`. For Google Docs it is
  `doc:<document-id>`.
- Read email query patterns and ignored-author lists from
  `config/sources.yaml` — do not hardcode them.
