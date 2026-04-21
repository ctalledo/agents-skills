# Check Jira Procedure

This procedure checks Jira for issues assigned to or
mentioning Cesar. It is run as a forked subagent by the
sitrep and concierge skills.

Jira integration is via the Atlassian MCP server plugin.

The tool invocations and JQL queries below are recommended
starting points. Adapt them to the projects, volume, and
current task.

## Configuration

Read the Jira user and projects from `config/sources.yaml`:

```yaml
jira:
  user: cesar.talledo
  projects:
    - MCP
```

Read the last checkpoint and capture the scan start time:

```bash
wl state checkpoint get jira
scan_started_at="$(wl util now --format iso)"
```

If the checkpoint is empty (first run), use a default of
7 days ago.

## Before Step 0: Initialize the Scan Log

Create the scan log file before issuing any API queries:

```bash
scan_log="$(wl scan init jira)"
```

This returns the absolute path to the scan log. All
enumerated issue keys are written to this file as `- [ ]`
items during Phase 1. Phase 2 classifies them and updates
the items to `- [x]` with labels.

## Step 0: Discover the Cloud ID

The Atlassian MCP tools require a `cloudId` parameter
for every request. Discover it using:

```
mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources({})
```

This returns a list of accessible Atlassian sites. Find
the entry for Docker's Jira instance and note the `id`
field — this is the `cloudId` to use in all subsequent
calls.

Cache this value for the duration of the session. If this
procedure is called multiple times, only discover the
cloud ID once.

## Phase 1: Enumerate Issues

The goal of Phase 1 is to enumerate all relevant issue
keys to the scan log before classifying any of them.

### Step 1: Search for Assigned Issues

Use JQL to find issues assigned to Cesar that have been
updated recently:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql({
    "cloudId": "<CLOUD_ID>",
    "jql": "assignee = \"cesar.talledo\" AND updated >= \"<CHECKPOINT_DATE>\" ORDER BY updated DESC",
    "fields": [
        "summary", "status", "priority",
        "updated", "assignee", "issuetype"
    ],
    "maxResults": 50,
    "responseContentFormat": "markdown"
})
```

Key parameters:
- **`cloudId`**: From Step 0.
- **`jql`**: JQL query string. Use the username from
  `config/sources.yaml` under `jira.user`.
- **`fields`**: Request only the fields needed to classify
  the issue. Omit `description` for the initial scan to
  keep responses small.
- **`maxResults`**: Max 100. Start with 50.
- **`responseContentFormat`**: Use `"markdown"` for
  readable output.

The checkpoint date in JQL uses the format `YYYY-MM-DD`
or `YYYY-MM-DD HH:mm` — not ISO 8601. Convert the
checkpoint timestamp accordingly with:

```bash
checkpoint_jql="$(wl util iso-to-jql "$checkpoint")"
```

#### Pagination

If the response includes a `nextPageToken` field, there
are more results. Paginate by passing the token to the
next request:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql({
    "cloudId": "<CLOUD_ID>",
    "jql": "<SAME_JQL>",
    "fields": [
        "summary", "status", "priority",
        "updated", "assignee", "issuetype"
    ],
    "maxResults": 50,
    "nextPageToken": "<TOKEN_FROM_PREVIOUS_RESPONSE>",
    "responseContentFormat": "markdown"
})
```

Continue until the response does not include a
`nextPageToken`.

After each page, append each issue key to the scan log
as an unchecked `- [ ]` line under `## Items`:

```
- [ ] `jira:<KEY>` — <SUMMARY> — (pending)
```

Record the page in `## Pagination Log`:

```
- Page N: M issues (token: <TOKEN>).
```

### Step 2: Search for Mentioned Issues

Search for issues where Cesar is mentioned (in comments
or description) but not necessarily assigned:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql({
    "cloudId": "<CLOUD_ID>",
    "jql": "text ~ \"cesar.talledo\" AND updated >= \"<CHECKPOINT_DATE>\" AND assignee != \"cesar.talledo\" ORDER BY updated DESC",
    "fields": [
        "summary", "status", "priority",
        "updated", "assignee", "issuetype"
    ],
    "maxResults": 20,
    "responseContentFormat": "markdown"
})
```

Also search within the monitored projects for recent
activity:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql({
    "cloudId": "<CLOUD_ID>",
    "jql": "project = MCP AND updated >= \"<CHECKPOINT_DATE>\" AND status changed ORDER BY updated DESC",
    "fields": [
        "summary", "status", "priority",
        "updated", "assignee", "issuetype"
    ],
    "maxResults": 30,
    "responseContentFormat": "markdown"
})
```

Read the project list from `config/sources.yaml` under
`jira.projects`. Apply the same pagination logic and
append new issue keys to the scan log (skip duplicates
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

For issues that appear to need attention, fetch full
details:

```
mcp__plugin_atlassian_atlassian__getJiraIssue({
    "cloudId": "<CLOUD_ID>",
    "issueIdOrKey": "MCP-456",
    "fields": [
        "summary", "description", "status",
        "priority", "comment", "assignee",
        "issuetype", "updated"
    ],
    "responseContentFormat": "markdown"
})
```

Only fetch full details selectively — do not fetch every
issue individually.

### Step 4: Classify Findings

#### Action Required

- Issues assigned to Cesar with status changes requiring
  action (e.g., moved to "In Progress", "In Review",
  "Blocked").
- Issues where Cesar is mentioned in a recent comment
  asking for input or review.
- New issues assigned to Cesar since the last check.
- Blocked issues in Cesar's projects.

#### Status Update Only

- Issues that have progressed but don't need Cesar's
  immediate action.
- Issues completed by others in monitored projects.
- FYI comments on watched issues.

#### Completed / Resolved

- Issues moved to "Done", "Closed", or "Resolved" since
  the last check. These may correspond to worklog threads
  that should be completed.

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

Jira-specific requirements:

- Set `source: jira`.
- Set `scan_started_at` to the value captured at the
  start of the check.
- Set `scan_log_path` to the worklog-relative path of
  the scan log.
- Set `proposed_state_updates.checkpoint = scan_started_at`.
- Use canonical `jira:<issue-key>` refs.

## Tips

- Keep `fields` lists minimal in search queries. Only
  request `description` and `comment` when fetching
  individual issues that need deeper inspection.
- Use `responseContentFormat: "markdown"` for readable
  output rather than the default ADF format.
- If an Atlassian MCP call fails (auth, rate limit,
  network), report the failure and continue with other
  queries. Do not retry aggressively.
- If a Jira issue is also tracked in Linear or referenced
  in a GitHub PR, note all cross-references in the
  findings so the sitrep can correlate them.
- JQL date format is `YYYY-MM-DD` or `YYYY-MM-DD HH:mm`,
  NOT ISO 8601. Convert checkpoint timestamps accordingly.
- Complete Phase 1 (all pagination) before starting
  Phase 2. The scan log is the handoff point.

## Constraints

- This procedure is read-only: it fetches and classifies
  but does not modify Jira issues or update the Jira
  checkpoint directly.
- All Jira interaction goes through the Atlassian MCP
  server plugin.
- The `cloudId` must be included in every Atlassian MCP
  tool call. Discover it once via
  `getAccessibleAtlassianResources` and reuse it for the
  session.
- The canonical worklog source ref format is
  `jira:<issue-key>` (e.g., `jira:MCP-456`).
- Read user, project list, and other config from
  `config/sources.yaml` — do not hardcode them.
