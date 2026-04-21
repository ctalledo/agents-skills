# Check Linear Procedure

This procedure checks Linear for issues assigned to or
mentioning Jacob. It is run as a forked subagent by the
sitrep and concierge skills.

Linear integration is via the Linear MCP server plugin.

The tool invocations below are recommended starting points.
Adapt filters and limits to the volume of issues.

## Configuration

Read the Linear user from `config/sources.yaml`:

```yaml
linear:
  user: jacob
```

Read the last checkpoint and capture the scan start time:

```bash
wl state checkpoint get linear
scan_started_at="$(wl util now --format iso)"
```

If the checkpoint is empty (first run), use a default of
7 days ago (ISO 8601 format, e.g., `-P7D` or an explicit
date).

## Before Step 1: Initialize the Scan Log

Create the scan log file before issuing any API queries:

```bash
scan_log="$(wl scan init linear)"
```

This returns the absolute path to the scan log. All
enumerated issue IDs are written to this file as `- [ ]`
items during Phase 1. Phase 2 classifies them and updates
the items to `- [x]` with labels.

## Phase 1: Enumerate Issues

The goal of Phase 1 is to enumerate all relevant issue
IDs to the scan log before classifying any of them.

### Step 1: Fetch Assigned Issues

Use the `list_issues` MCP tool to get issues assigned to
Jacob that have been updated since the last checkpoint:

```
mcp__plugin_linear_linear__list_issues({
    "assignee": "me",
    "updatedAt": "<CHECKPOINT_ISO8601>",
    "orderBy": "updatedAt",
    "limit": 50
})
```

Key parameters:
- **`assignee`**: Use `"me"` for the authenticated user.
- **`updatedAt`**: ISO 8601 date or duration (e.g.,
  `"2026-03-11T00:00:00Z"` or `"-P1D"` for last day).
- **`orderBy`**: Sort by `"updatedAt"` to see the most
  recently changed issues first.
- **`limit`**: Max 250, default 50. Increase if needed.

#### Pagination

If the response includes a `cursor` field, there are more
results. Paginate by passing the cursor to the next
request:

```
mcp__plugin_linear_linear__list_issues({
    "assignee": "me",
    "updatedAt": "<CHECKPOINT_ISO8601>",
    "orderBy": "updatedAt",
    "limit": 50,
    "cursor": "<CURSOR_FROM_PREVIOUS_RESPONSE>"
})
```

Continue until the response does not include a `cursor`
field. This is important when the checkpoint is old
(e.g., after a vacation) and many issues have accumulated.

After each page, append each issue to the scan log as an
unchecked `- [ ]` line under `## Items`:

```
- [ ] `linear:<ISSUE_ID>` `<IDENTIFIER>` — <TITLE> — (pending)
```

Record the page in `## Pagination Log`:

```
- Page N: M issues (cursor: <CURSOR>).
```

### Step 2: Check for Mentions

Linear does not have a direct "mentioned" filter in the
`list_issues` API. To find issues where Jacob is mentioned
but not assigned, use a keyword search:

```
mcp__plugin_linear_linear__list_issues({
    "query": "jacob",
    "updatedAt": "<CHECKPOINT_ISO8601>",
    "orderBy": "updatedAt",
    "limit": 20
})
```

Apply the same pagination logic as in Step 1. Append
any new issue IDs to the scan log (skip duplicates
already added in Step 1).

After all enumeration is complete, update the scan log
frontmatter:

```bash
yq --front-matter=process \
    '.pagination.pages = N | .pagination.total_items = T | .pagination.phase1_complete = true' \
    -i "$scan_log"
```

## Phase 2: Classify Issues

Read the `- [ ]` items from the scan log and classify
each one. Process in batches of 20–30.

### Step 3: Get Details for Key Issues

For issues that appear to need attention (status changes,
new comments, blockers), fetch full details:

```
mcp__plugin_linear_linear__get_issue({
    "id": "<ISSUE_ID>",
    "includeRelations": true
})
```

The `includeRelations` flag shows blocking/blocked-by
relationships, which are useful for identifying blockers.

Only fetch full details for issues that are likely
actionable — do not fetch details for every issue in the
list.

For mention candidates that look important, confirm the
actual comment context with `list_comments` before
classifying them as actionable:

```
mcp__plugin_linear_linear__list_comments({
    "issueId": "<ISSUE_ID>",
    "orderBy": "updatedAt",
    "limit": 20
})
```

### Step 4: Classify Findings

#### Action Required

- Issues assigned to Jacob with status changes requiring
  action (e.g., moved to "In Progress", "In Review").
- Issues where Jacob is mentioned in a recent comment
  asking for input.
- Blocked issues assigned to Jacob.
- New issues assigned to Jacob since the last check.

#### Status Update Only

- Issues that have progressed (status moved forward) but
  don't require immediate action.
- Issues where comments are FYI.
- Completed issues that can be correlated with worklog
  threads for closure.

#### Completed / Resolved

- Issues that have been moved to "Done" or "Cancelled"
  since the last check. These may correspond to worklog
  threads that should be completed.

After classifying each batch, update the scan log items
from `- [ ]` to `- [x]` with the appropriate label
(`**action-required**`, `**status-update**`,
`**completed**`, `**ignored**`).

After all items are classified, update the scan log
frontmatter:

```bash
yq --front-matter=process '
    .status = "ok" |
    .pagination.phase2_complete = true |
    .classified.action_required = A |
    .classified.status_update = S |
    .classified.completed = C |
    .classified.ignored = I
' -i "$scan_log"
```

Use `status: "partial"` if some batches failed.

## Step 5: Return Structured Findings

Return a single YAML block using the shared findings
schema in `findings-schema.md`.

Linear-specific requirements:

- Set `source: linear`.
- Set `scan_started_at` to the value captured at the
  start of the check.
- Set `scan_log_path` to the worklog-relative path of
  the scan log.
- Set `proposed_state_updates.checkpoint = scan_started_at`.
- Use canonical `linear:<issue-identifier>` refs.

## Tips

- Use `list_issues` for bulk queries rather than
  `get_issue` one by one — it is faster and more
  context-efficient.
- If a Linear MCP call fails, report the failure and
  continue. Do not retry aggressively.
- The keyword search for mentions (Step 2) is best-effort.
  Expect some false positives from coincidental keyword
  matches — filter them during classification.
- If an issue is also tracked in Jira, note both
  references in the findings so the sitrep can correlate
  them.
- Complete Phase 1 (all pagination) before starting
  Phase 2. The scan log is the handoff point.

## Constraints

- This procedure is read-only: it fetches and classifies
  but does not modify Linear issues or update the Linear
  checkpoint directly.
- All Linear interaction goes through the Linear MCP
  server plugin.
- The canonical worklog source ref format is
  `linear:<issue-identifier>` (e.g., `linear:MCP-123`).
- Linear issue identifiers use a team prefix and number
  (e.g., `MCP-123`, `PLAT-456`).
- Read the Linear user from `config/sources.yaml` — do
  not hardcode it.
