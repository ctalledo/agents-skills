# Check Slack Procedure

This procedure checks monitored Slack channels for new
messages and @-mentions of Cesar. It is run as a forked
subagent by the sitrep and concierge skills.

Slack integration is via the Slack MCP server plugin.

The tool invocations below are recommended starting points.
Adapt response formats, limits, and pagination to the
volume of messages in each channel.

## Configuration

Read the channel list from `config/sources.yaml` under
`slack.channels`. Channels are grouped by priority tier:

- **mcp** (high priority): MCP team channels.
- **ai** (medium priority): AI initiative channels.
- **general** (low priority): General Docker channels.

Read Cesar's Slack user ID:

```yaml
slack:
  user_id: U059HQR5WLR
```

Read the current cursors:

```bash
wl state cursor list
```

At the start of the check, capture the scan start time:

```bash
scan_started_at="$(wl util now --format iso)"
```

For each channel, the cursor's `last_ts` value is the
timestamp of the last-read message. If no cursor exists
for a channel (first check), read only recent messages
(set `oldest` to a timestamp ~24 hours ago). Use
`wl util now --format iso` plus `wl util iso-to-slack`
to derive explicit default values when needed.

## Before Step 1: Initialize the Scan Log

Each Slack subagent creates its own scan log, scoped to
the channels it processes. The source name matches the
subagent role:

| Subagent role | Source name |
|---|---|
| mcp-tier channels | `slack-mcp` |
| ai-tier channels | `slack-ai` |
| general-tier channels | `slack-general` |
| DMs and @-mentions | `slack-mentions` |
| Watched work threads | `slack-watched` |

```bash
scan_log="$(wl scan init slack-mcp)"   # or slack-ai, etc.
```

This returns the absolute path to the scan log. All
enumerated message and thread IDs are written to this
file as `- [ ]` items during Phase 1. Phase 2 classifies
them and updates the items to `- [x]` with labels.

## Phase 1: Enumerate Messages

The goal of Phase 1 is to enumerate all relevant message
timestamps to the scan log before classifying any of them.

## Step 1: Read Channels by Priority

Process channels in priority order: mcp first, then ai,
then general. For each channel:

### 1a. Get the Cursor

```bash
wl state cursor get <CHANNEL_ID>
```

If empty, compute a default oldest timestamp (24 hours
ago, in Slack timestamp format — Unix epoch seconds with
a decimal, e.g., `"1741148400.000000"`).

### 1b. Read New Messages

Use the `slack_read_channel` MCP tool:

```
mcp__plugin_slack_slack__slack_read_channel({
    "channel_id": "<CHANNEL_ID>",
    "oldest": "<CURSOR_LAST_TS>",
    "limit": 100,
    "response_format": "concise"
})
```

Key parameters:
- **`channel_id`**: The channel ID from sources.yaml.
- **`oldest`**: The cursor timestamp. Only messages newer
  than this will be returned.
- **`limit`**: Max 100 messages per call. If the response
  includes a `cursor` field, there are more messages.
  Paginate by passing the cursor to the next request (see
  Pagination below).
- **`response_format`**: Use `"concise"` to reduce response
  size. Switch to `"detailed"` only if more context is
  needed for a specific message.

#### Pagination

If the response includes a `cursor` field, there are more
messages than the `limit` returned. Fetch the next page:

```
mcp__plugin_slack_slack__slack_read_channel({
    "channel_id": "<CHANNEL_ID>",
    "oldest": "<CURSOR_LAST_TS>",
    "limit": 100,
    "cursor": "<CURSOR_FROM_PREVIOUS_RESPONSE>",
    "response_format": "concise"
})
```

Continue until the response does not include a `cursor`
field or returns fewer than `limit` messages.

### 1c. Append to Scan Log

After each page, append each message to the scan log as
an unchecked `- [ ]` line under `## Items`:

```
- [ ] `slack:<CHANNEL_ID>/<TS>` — @<author> — <snippet> — (pending)
```

Record the page in `## Pagination Log`:

```
- <CHANNEL_ID> page N: M messages (cursor: <CURSOR>).
```

### 1d. Propose the Cursor Update

After processing a channel's messages, record the newest
message timestamp as a **proposed** cursor update. Do not
call `wl state cursor set` here. This subagent is
read-only.

After all channels are enumerated, update the scan log
frontmatter:

```bash
yq --front-matter=process \
    '.pagination.pages = N | .pagination.total_items = T | .pagination.phase1_complete = true' \
    -i "$scan_log"
```

## Step 2: Search for DMs and @-Mentions

This step is performed only by the `slack-mentions`
subagent. Skip it in the channel-tier subagents.

In addition to reading monitored channels, run two
searches to find messages directed at Cesar.

Read Cesar's user ID from `slack.user_id` in
`config/sources.yaml`.

To scope both searches to recent messages, use the
`after` parameter with a Unix timestamp. Derive it as
follows — never use a pre-computed value passed in from
the calling context, as manual conversions are error-prone:

```bash
# Use the mentions cursor if it exists.
mentions_cursor="$(wl state cursor get mentions)"

# If empty, fall back to the source checkpoint converted
# to Unix seconds.  Use iso-to-unix, not a manual
# calculation.
if [ -z "$mentions_cursor" ]; then
    checkpoint="$(wl state checkpoint get slack 2>/dev/null \
        || wl util now --format iso)"
    mentions_cursor="$(wl util iso-to-unix "$checkpoint")"
fi
```

Use `$mentions_cursor` as the `after` value in both
searches below.

### 2a. DMs (`to:me`)

Search for direct messages sent to Cesar. The `to:me`
modifier matches messages in DM conversations:

```
mcp__plugin_slack_slack__slack_search_public_and_private({
    "query": "to:me",
    "channel_types": "im,mpim",
    "after": "<UNIX_TIMESTAMP>",
    "sort": "timestamp",
    "sort_dir": "desc",
    "limit": 20,
    "include_context": true,
    "max_context_length": 200,
    "response_format": "concise"
})
```

This tool may require an explicit consent prompt because
it searches private conversations. If consent is not
granted, record a failure for `dm-search` and continue
with the rest of the Slack check.

### 2b. @-Mentions (`<@USER_ID>`)

Search for messages that @-mention Cesar. Use the user
ID as a **plain keyword** — do NOT use the `to:` search
modifier, which only matches DMs and does not find
@-mentions in channels or thread replies:

```
mcp__plugin_slack_slack__slack_search_public_and_private({
    "query": "<@U059HQR5WLR>",
    "channel_types": "public_channel,private_channel,im,mpim",
    "after": "<UNIX_TIMESTAMP>",
    "sort": "timestamp",
    "sort_dir": "desc",
    "limit": 20,
    "include_context": true,
    "max_context_length": 200,
    "response_format": "concise"
})
```

This catches @-mentions in channels that are not in the
monitored list, as well as mentions in thread replies
(which do not appear in channel reads).

This search may also require an explicit consent prompt
because it spans private channels and DMs. If consent is
not granted, record a failure for `mention-search` and
continue.

### Pagination for Searches

Both DM and @-mention searches return at most `limit`
results per call. If the response includes a `cursor`
field, paginate to retrieve additional results by passing
the cursor to the next request:

```
mcp__plugin_slack_slack__slack_search_public_and_private({
    "query": "<ORIGINAL_QUERY>",
    "channel_types": "<ORIGINAL_TYPES>",
    "after": "<UNIX_TIMESTAMP>",
    "sort": "timestamp",
    "sort_dir": "desc",
    "limit": 20,
    "cursor": "<CURSOR_FROM_PREVIOUS_RESPONSE>",
    "include_context": true,
    "max_context_length": 200,
    "response_format": "concise"
})
```

Continue until the response does not include a `cursor`
field.

Append search result message timestamps to the scan log
as `- [ ]` items, same as channel messages.

## Step 3: Read Watched Work Threads

This step is performed only by the `slack-watched`
subagent. Skip it in the channel-tier and mentions
subagents.

Active worklog threads that contain Slack sources are
implicitly watched until the work item is done. Enumerate
them with:

```bash
wl thread watched-slack --json
```

Each watch object includes:

- `cursor_key`: The cursor to use for this watched thread
  (for example
  `watch-slack:C08J27QSJJJ/1741234560.000000`).
- `thread_ts`: The parent/root Slack thread timestamp to
  pass to `slack_read_thread`.
- `default_oldest_ts`: The fallback lower bound to use if
  the watch cursor is not yet present.
- `thread_ids`: The owning worklog thread IDs that should
  receive any correlated updates.

For each watched thread:

1. Read the existing watch cursor:
   `wl state cursor get <cursor_key>`
2. If it is empty, use `default_oldest_ts`.
3. Read the thread:

```
mcp__plugin_slack_slack__slack_read_thread({
    "channel_id": "<CHANNEL_ID>",
    "message_ts": "<THREAD_TS>",
    "oldest": "<WATCH_CURSOR_OR_DEFAULT>",
    "response_format": "concise"
})
```

4. Append any new replies to the scan log as `- [ ]`
   items.
5. Propose a cursor update for the same `cursor_key`.

Append watched thread replies to the scan log:

```
- [ ] `slack:<CHANNEL_ID>/<REPLY_TS>?thread=<PARENT_TS>` — @<author> — <snippet> — (pending)
```

After all enumeration is complete, update the scan log
frontmatter `phase1_complete: true`.

## Phase 2: Classify Messages

Read the `- [ ]` items from the scan log and classify
each one. Process in batches of 20–30.

## Step 4: Read Additional Relevant Threads

If a message in a monitored channel has replies that
seem relevant (e.g., it's a thread Cesar was mentioned
in, or a thread about a topic in the worklog), read the
thread for context:

```
mcp__plugin_slack_slack__slack_read_thread({
    "channel_id": "<CHANNEL_ID>",
    "message_ts": "<THREAD_PARENT_TS>",
    "response_format": "concise"
})
```

Only do this selectively — not for every thread. Focus
on threads that:
- Mention Cesar directly.
- Relate to active worklog threads.
- Appear to require a response or decision.

## Step 5: Classify Findings

### Action Required

- Direct @-mentions asking Cesar a question or requesting
  input.
- Messages in high-priority channels that require a
  response (decisions, review requests, blockers).
- Threads where Cesar was asked to follow up.

### Status Update Only

- General discussion in monitored channels about ongoing
  projects.
- FYI messages about deployments, releases, or status
  changes.
- Messages that reference active worklog threads but
  don't require action.

### Ignorable

- Bot messages (unless they indicate a failure).
- Social/off-topic conversation.
- Messages in low-priority channels with no relevance to
  current worklog threads.

After classifying each batch, update the scan log items
from `- [ ]` to `- [x]` with the appropriate label.

After all items are classified, update the scan log
frontmatter:

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

Use `status: "partial"` if some channels or searches
failed.

When returning a finding derived from a watched thread,
include the owning worklog thread IDs in the finding's
`metadata.worklog_thread_ids` field.

## Step 6: Return Structured Findings

Return a single YAML block using the shared findings
schema in `findings-schema.md`.

Slack-specific requirements:

- Set `source: slack`.
- Set `scan_started_at` to the value captured at the
  start of the check.
- Set `scan_log_path` to the worklog-relative path of
  the scan log.
- `summary.checked` should count channels, watched
  threads, and any DM / mention searches that actually
  ran.
- Include a `failures` entry for every skipped or failed
  DM / mention search.
- `proposed_state_updates.cursors` must include an entry
  for **every** channel checked, even those with 0 new
  messages.
- Store the DM / mention search cursor under the
  `mentions` key in `proposed_state_updates.cursors` if
  either search ran successfully.
- Store watched-thread cursor updates using `watch-slack`
  cursor keys for every watched Slack thread that was
  polled.
- Never describe the cursor updates as already applied.
  They are always proposed.

## Batching for Large Channel Lists

When checking many channels (30+), batch by priority
tier. The sitrep skill may fork separate subagents per
tier for parallelism. Within a single subagent, process
channels sequentially.

Recommended batching:
- **Batch 1** (high priority): All `mcp` tier channels.
- **Batch 2** (medium priority): All `ai` tier channels.
- **Batch 3** (low priority): All `general` tier channels.

## Tips

- If a channel has a very high volume of messages since
  the last cursor, complete Phase 1 for all channels
  before starting Phase 2. The scan log is the handoff
  point.
- If a Slack MCP call fails (timeout, rate limit), report
  the failure for that channel and continue with others.
  Do not retry aggressively.
- Read user profiles (`slack_read_user_profile`) sparingly
  — only when you need to resolve a user ID to a name for
  classification purposes.
- `slack_read_channel` returns messages newest-first. When
  proposing a cursor update, use the maximum `ts` observed
  during the scan, not the last message in the response.

## Constraints

- This procedure is read-only. It reads and classifies
  but does not mark messages as read or update any
  cursors. Slack read-state is managed manually by Cesar.
- All Slack interaction goes through the Slack MCP server
  plugin. There is no CLI fallback.
- Read the channel list and user ID from
  `config/sources.yaml` — do not hardcode them.

## Reference

- Slack message timestamps (e.g., `1741234567.123456`)
  are the primary identifier for messages. They are also
  used as cursor values. Always preserve the dot in the
  timestamp — it is part of the canonical format.
- The canonical worklog source ref format for Slack is:
  - **Standalone message or thread parent**:
    `slack:<channel-id>/<message-ts>`
    (e.g., `slack:C08J27QSJJJ/1741234567.123456`).
  - **Thread reply**:
    `slack:<channel-id>/<message-ts>?thread=<parent-ts>`
    (e.g.,
    `slack:C08J27QSJJJ/1741234590.654321?thread=1741234567.123456`).
    The `thread` parameter is the `thread_ts` of the
    parent message. Include it whenever the message is a
    reply within a thread (i.e., when `thread_ts` differs
    from the message's own `ts`).
  - When a finding is about an entire thread (not a
    specific reply), use the **parent message's `ts`** as
    the `<message-ts>` and omit the `?thread=` suffix.
- When extracting message timestamps from Slack API
  responses, always use the `ts` field of the message
  object. Do not use search result metadata, permalink
  fragments, or other derived values — these may be
  truncated or formatted differently. The `ts` field
  always contains the full precision timestamp with a
  dot (e.g., `1741234567.123456`).
- Use `response_format: "concise"` by default to minimize
  context usage. Only escalate to `"detailed"` when
  more context is needed for classification.
- The Slack MCP server cannot mark messages as read. That
  is managed manually by Cesar.
