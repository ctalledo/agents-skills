# Findings Schema

All sitrep source-check subagents are **read-only**. They do
not update the worklog, cursors, checkpoints, notifications,
or any external system. They return a structured findings
document that the parent agent correlates into a proposed
changeset.

The parent agent is the **single writer**. It alone may:

- Create, update, complete, or revive worklog threads.
- Advance cursors or checkpoints.
- Commit the worklog repository.
- Clean up notifications after the commit succeeds and
  Jacob confirms the cleanup list.

## Output Format

Return a single fenced YAML block matching this shape:

```yaml
source: slack                # github | email | slack |
                             #   linear | jira
status: ok                   # ok | partial | failed
scan_started_at: 2026-03-13T23:00:00Z
scan_log_path: "sitreps/scans/2026-03-13T230000Z-slack.md"
summary:
  checked: 12
  action_required: 2
  status_updates: 5
  completed: 1
failures:
  - scope: "dm-search"
    error: "Slack MCP search timed out."
action_required:
  - kind: mention
    title: "Jacob asked to review gateway config changes"
    summary: "Question from @teammate in #team-mcp-tools-security."
    priority_hint: high
    refs:
      - slack:C08J27QSJJJ/1741234567.123456
    urls:
      - "https://docker.slack.com/archives/C08J27QSJJJ/p1741234567123456"
    metadata:
      channel_id: C08J27QSJJJ
      channel_name: team-mcp-tools-security
status_updates:
  - kind: deploy
    title: "PR #567 merged and deployed"
    summary: "FYI only."
    refs:
      - github:docker/mcp-gateway#567
completed:
  - kind: merged
    title: "PR #567 merged"
    summary: "Active thread can be completed if it exists."
    refs:
      - github:docker/mcp-gateway#567
cleanup:
  github_notification_ids: []   # GitHub only.
  email_message_ids: []         # Email only.
proposed_state_updates:
  checkpoint: 2026-03-13T23:00:00Z
  cursors:                      # Slack only.
    - key: C08J27QSJJJ
      last_ts: "1741234590.123456"
    - key: watch-slack:C08J27QSJJJ/1741234560.000000
      last_ts: "1741234590.123456"
```

## Field Semantics

- `scan_started_at` is captured **before** any source query is
  issued. This is the only safe value to propose as the next
  checkpoint after a successful run.
- `scan_log_path` is the worklog-relative path to the scan
  log file created during this check (e.g.,
  `sitreps/scans/2026-03-19T143645Z-email.md`). Optional.
  When present, the parent sitrep agent includes this path
  in the commit so the scan log is persisted. If the check
  did not use a scan log, omit this field.
- `status` is:
  - `ok` when the whole source check completed.
  - `partial` when some scopes failed but useful findings were
    still produced.
  - `failed` when no useful findings were produced.
- `summary.checked` is source-specific:
  - GitHub: notifications/PRs inspected.
  - Email: messages inspected.
  - Slack: channels or searches inspected.
  - Linear/Jira: issues inspected.
- `refs` use canonical worklog source-ref formats.
- `cleanup` contains identifiers for cleanup that happens
  **after** worklog commit and explicit Jacob approval.
  Cleanup lists may contain identifiers for items that have
  no corresponding finding. For example, emails from ignored
  authors are included in `cleanup.email_message_ids` even
  though they do not generate findings. The parent agent
  must process **all** cleanup identifiers regardless of
  whether a matching finding exists.
- `proposed_state_updates` contains values the parent agent
  may apply later. Subagents never apply them themselves.
- Slack cursor keys may be channel IDs, `mentions`, or
  watch keys of the form
  `watch-slack:<channel-id>/<thread-ts>`.

## Requirements

- Omit irrelevant cleanup arrays only if the entire `cleanup`
  block is empty; otherwise include the block explicitly.
- Omit irrelevant `cursors` only if the source is not Slack.
- Include every failure in `failures`, even when the overall
  source check is `partial`.
- If a source check is `failed`, still return the YAML block
  with empty findings lists and the recorded failure.
