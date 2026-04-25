# Check Notion Procedure

This procedure checks monitored Notion pages for recently
created or updated content that may require action. It is
run as a forked subagent by the sitrep and concierge skills.

Notion integration is via the Notion MCP server plugin.

The tool invocations below are recommended starting points.
Adapt query terms, page limits, and filtering to the volume
of content in each monitored page.

## Configuration

Read the monitored pages from `config/sources.yaml` under
`notion.pages`. Each entry has an `id`, `name`, and `url`.
Sub-pages are implicitly included by scoping searches to
the configured root page.

Read the last checkpoint and capture the scan start time:

```bash
checkpoint="$(wl state checkpoint get notion)"
scan_started_at="$(wl util now --format iso)"
```

If the checkpoint is empty (first run), use a default of
7 days ago:

```bash
checkpoint="$(
    wl util add-weekday-hours "$scan_started_at" -168
)"
```

Convert the checkpoint to a date string for Notion's
`created_date_range` filter (which requires `YYYY-MM-DD`):

```bash
# Extract just the date portion (first 10 characters).
checkpoint_date="${checkpoint:0:10}"
```

## Before Step 1: Initialize the Scan Log

Create the scan log file before issuing any API queries:

```bash
scan_log="$(wl scan init notion)"
```

This returns the absolute path to the scan log. All
enumerated page IDs are written to this file as `- [ ]`
items during Phase 1. Phase 2 classifies them and updates
the items to `- [x]` with labels.

## Phase 1: Enumerate Pages

The goal of Phase 1 is to enumerate all relevant Notion
page IDs to the scan log before classifying any of them.

Process each configured root page from `sources.yaml`.

### Step 1: Find Recently Created Pages

Use `notion-search` scoped to the root page with a
`created_date_range` filter to find pages newly created
since the last checkpoint:

```
mcp__plugin_Notion_notion__notion-search({
    "query": "notes update agenda decision announcement",
    "query_type": "internal",
    "page_url": "<ROOT_PAGE_ID_OR_URL>",
    "filters": {
        "created_date_range": {
            "start_date": "<CHECKPOINT_DATE>"
        }
    },
    "page_size": 25,
    "max_highlight_length": 150
})
```

Key parameters:
- **`query`**: A broad set of common content terms.
  Notion uses semantic search, so including varied terms
  improves recall.
- **`page_url`**: The root page ID or URL from
  `sources.yaml`. This scopes the search to that page and
  all its sub-pages.
- **`filters.created_date_range.start_date`**: The
  checkpoint date in `YYYY-MM-DD` format.
- **`page_size`**: Max 25. Use the maximum to reduce
  calls.

If the response includes fewer than 25 results, Phase 1 is
complete for newly created pages. If 25 are returned,
there may be more — repeat the search with additional
query terms (such as `"meeting review status report"`)
to increase coverage. Notion search does not support
pagination cursors; use varied query terms as a proxy.

After each search, append new page IDs to the scan log as
unchecked `- [ ]` lines under `## Items`. Skip duplicates:

```
- [ ] `notion:<PAGE_ID>` — <TITLE> — created <DATE> — (pending)
```

Record the search in `## Pagination Log`:

```
- Search "<QUERY>" in <ROOT_PAGE_NAME>: N results.
```

### Step 2: Find Recently Updated Pages

Notion's search API does not expose a modified-date filter.
To catch updates to existing pages, run a broad semantic
search scoped to the root page without a date filter, then
filter by the `timestamp` field in the results (which
reflects last-modified time):

```
mcp__plugin_Notion_notion__notion-search({
    "query": "meeting notes update agenda status",
    "query_type": "internal",
    "page_url": "<ROOT_PAGE_ID_OR_URL>",
    "filters": {},
    "page_size": 25,
    "max_highlight_length": 150
})
```

From the results, include only pages whose `timestamp`
field is later than the checkpoint. For each such page
that is not already in the scan log, append it:

```
- [ ] `notion:<PAGE_ID>` — <TITLE> — updated <TIMESTAMP> — (pending)
```

Run this search two or three times with different query
terms (e.g., `"decision announcement plan roadmap"`,
`"review feedback comment thread"`) to improve coverage.
Add only pages newer than the checkpoint that are not
already in the scan log.

After all enumeration is complete, update the scan log
frontmatter:

```bash
yq --front-matter=process \
    '.pagination.pages = N | .pagination.total_items = T | .pagination.phase1_complete = true' \
    -i "$scan_log"
```

## Phase 2: Classify Pages

Read the `- [ ]` items from the scan log and classify each
one. Process in batches of 10–20 (Notion page content can
be long).

### Step 3: Fetch Page Contents

For each enumerated page, fetch its full content using
`notion-fetch`:

```
mcp__plugin_Notion_notion__notion-fetch({
    "id": "<PAGE_ID>"
})
```

Fetch selectively — prioritize pages with titles or
highlights that suggest action (meeting notes with action
items, decision documents, pages explicitly addressed to
Cesar). For pages that appear to be templates or purely
archival, skip the full fetch and classify from the
search snippet alone.

### Step 4: Classify Findings

#### Action Required

- Pages that assign action items or tasks to Cesar.
- Decision documents asking for Cesar's input or approval.
- Meeting notes where Cesar is mentioned in the context
  of an action item or follow-up.
- New announcements or policy changes affecting Cesar's
  team that require a response.

#### Status Update Only

- Meeting notes with no explicit action items for Cesar.
- Status reports or roadmap updates that are informational.
- Pages that reference ongoing work already tracked in the
  worklog.

#### Ignorable

- Template pages, archived pages, or formatting-only edits.
- Pages that are structurally similar to content already
  classified in a recent check.
- Pages outside Cesar's area of responsibility (e.g.,
  unrelated team content that surfaced via search).

After classifying each batch, update the scan log items
from `- [ ]` to `- [x]` with the appropriate label
(`**action-required**`, `**status-update**`, `**ignored**`).

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

Use `status: "partial"` if some pages could not be
fetched or classified.

## Step 5: Return Structured Findings

Return a single YAML block using the shared findings schema
in `findings-schema.md`.

Notion-specific requirements:

- Set `source: notion`.
- Set `scan_started_at` to the value captured at the start
  of the check.
- Set `scan_log_path` to the worklog-relative path of the
  scan log.
- Set `proposed_state_updates.checkpoint = scan_started_at`.
- Use canonical `notion:<page-id>` refs (UUID with dashes,
  e.g., `notion:30d57a1d-4673-8058-8be0-d3308fdcebf3`).
- Include a Notion page URL for every finding under `urls`
  (format: `https://www.notion.so/<page-id-no-dashes>`).
- `summary.checked` should count the number of pages
  inspected (fetched in Phase 2), not the number of search
  results.

## Tips

- Notion search is semantic, not keyword-exact. Use varied,
  natural-language query terms across multiple calls to
  maximize recall.
- The `timestamp` field in search results reflects the
  last-modified time. Use it to filter out pages that
  have not changed since the last checkpoint.
- If a page is a Notion database (type: database), fetch
  it to enumerate its rows. Each row is a child page —
  check rows for recently created or modified entries by
  searching within the database using `data_source_url`.
- If a Notion MCP call fails (auth, rate limit, network),
  record the failure for that page and continue. Do not
  retry aggressively.
- Prefer `max_highlight_length: 150` on search calls to
  keep response sizes manageable.

## Constraints

- This procedure is read-only. It fetches and classifies
  but does not modify any Notion pages or update the
  Notion checkpoint directly.
- All Notion interaction goes through the Notion MCP server
  plugin. There is no CLI fallback.
- Read page IDs and URLs from `config/sources.yaml` under
  `notion.pages` — do not hardcode them.
- The canonical worklog source ref format is
  `notion:<page-id>` (UUID with dashes, e.g.,
  `notion:30d57a1d-4673-8058-8be0-d3308fdcebf3`).
- Notion's search API provides a `created_date_range`
  filter but no `updated_date_range`. Filtering by the
  `timestamp` field in search results is the only way to
  detect updates to existing pages.
