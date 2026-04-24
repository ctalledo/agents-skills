---
name: worklog-report
description: >-
  Generate a report from worklog history. Supports standup, weekly, monthly,
  quarterly, and custom date ranges. Useful for standups, manager discussions,
  and performance reviews.
disable-model-invocation: true
argument-hint: "[standup|weekly|monthly|quarterly|custom <start> <end>|sitrep]"
compatibility: >-
  Requires the wl tool in the worklog repository.
---

# Worklog Report

Generate a structured report from the worklog repository, covering work threads
completed and in progress over a specified time period.

The worklog repository is at `worklog/` relative to the
directory where Claude was invoked. The `wl` CLI tool is at `$WORKLOG_PATH/tools/wl`, where
`$WORKLOG_PATH` is an environment variable. At the start,
resolve it once by running `printenv WORKLOG_PATH`. If the
output is empty, stop immediately and report:
"Error: WORKLOG_PATH is not set." Use the resolved absolute
path for all subsequent `wl` invocations — never
re-expand `$WORKLOG_PATH` inline in commands.

The report formats below are recommended templates, not rigid structures. Adapt
the level of detail and grouping to the report type and audience.

## Report Types

### `/worklog-report standup`

**Scope**: Yesterday and today.

**Format**: Brief, suitable for a daily standup meeting.

```
## Standup — 2026-03-12

### Yesterday
- Reviewed PR docker/mcp-gateway#1234 (approved with
  comments). [0000047]
- Addressed feedback on PR docker/ai-mcp#567, pushed
  updates. [0000043]

### Today (Planned)
- Follow up on MCP Gateway caching review. [0000047]
- Respond to Slack thread on enterprise auth. [0000048]
- Continue catalog schema migration. [0000002]

### Blockers
- Waiting on charlie's review of docker/ai-mcp#567
  (52h overdue). [0000043]
```

### `/worklog-report weekly`

**Scope**: Current calendar week (Monday through now).

**Format**: Grouped by day, with summary statistics.

```
## Weekly Report — 2026-W11 (Mar 9–15)

### Summary
- Completed: 5 threads
- In progress: 3 threads
- New: 7 threads
- PRs reviewed: 3
- PRs merged: 2

### Monday, Mar 9
- Created 0000041: Review PR docker/mcp-registry#567.
- Created 0000042: Jira MCP-456 schema migration.
...

### Tuesday, Mar 10
...

### Active Threads
(compact list of currently active threads)
```

### `/worklog-report monthly`

**Scope**: Current calendar month.

**Format**: Grouped by week, with summary statistics and
highlights.

```
## Monthly Report — March 2026

### Summary
- Completed: 18 threads
- PRs reviewed: 12
- PRs authored/merged: 4
- Design discussions: 3
- Incidents: 1

### Week 1 (Mar 1–7)
...

### Week 2 (Mar 8–14)
...

### Highlights
- Led design review for MCP Gateway enterprise auth.
- Completed catalog schema v4 migration.
- Resolved production incident in MCP registry.
```

### `/worklog-report quarterly`

**Scope**: Current quarter.

**Format**: High-level summary with categorized
accomplishments, suitable for performance reviews.

```
## Quarterly Report — 2026 Q1 (Jan–Mar)

### Summary
- Total threads: 87 completed, 12 active
- PRs reviewed: 45
- PRs authored/merged: 15
- Design contributions: 8
- Incidents handled: 3

### Key Accomplishments
1. Led MCP Gateway enterprise edition architecture and
   initial implementation.
2. Designed and implemented catalog schema v4 with
   backward compatibility.
3. Established MCP security review process and tooling.
...

### Themes
- MCP Platform: 60% of work
- AI Infrastructure: 25% of work
- Operational/Admin: 15% of work

### Active / Ongoing
(threads still in progress at quarter end)
```

### `/worklog-report custom <start> <end>`

**Scope**: Arbitrary date range.

**Format**: Adapts based on the range length — daily detail
for short ranges, weekly grouping for longer ranges.

### `/worklog-report sitrep`

**Scope**: Current state snapshot.

**Format**: Same as the sitrep presentation in the sitrep
skill, but saved as a report file. This is useful for
generating a point-in-time record without running the full
source-checking flow.

## Generating a Report

### Step 1: Gather Data

Use `wl` tool commands to gather the relevant data:

```bash
# Active threads.
wl thread list

# Threads created in the date range.
wl thread list --all --created-since <start-date> \
    --created-until <end-date>

# Threads completed in the date range.
wl thread list --all --completed-since <start-date> \
    --completed-until <end-date>

# Threads updated in the date range.
wl thread list --all --since <start-date> \
    --until <end-date>

# Thread statistics.
wl summary stats --since <start-date> --until <end-date>

# Recent commit history for activity context.
wl summary commits --since "<range>"
```

For individual thread details (activity logs), use
`wl thread get <id>` selectively — only for threads that
need more detail in the report.

Treat `created`, `updated`, and `completed_at` as distinct
timestamps with distinct meanings. Do not infer completion
dates from `updated` when `completed_at` is available.

### Step 2: Categorize Threads

Group threads by type for the report:
- **PR Reviews**: type `pr-review`
- **PR Management**: type `pr-feedback`
- **Development**: type `development`
- **Design**: type `design`
- **Incidents**: type `incident`
- **Admin**: type `admin`
- **Discussions**: type `discussion`

Within each category, sort by priority (critical first)
then by date.

### Step 3: Compute Statistics

Count threads by:
- Status (completed vs active vs blocked).
- Type (PR reviews, development, etc.).
- Priority (critical, high, medium, low).
- Time distribution (which weeks/days were busiest).

### Step 4: Generate the Report

Write the report in Markdown format. Adapt the format
based on the report type (see templates above).

For **standup** reports, pull activity log entries from
threads that were active yesterday and today in Cesar's
local timezone. Focus on what was done and what's planned.

For **weekly** and **monthly** reports, use thread creation
and completion dates to build a timeline. Use `created`
for "new" counts and `completed_at` for "completed"
counts.

For **quarterly** reports, synthesize themes and
highlights from the full set of completed threads. This
requires reading activity logs for significant threads to
extract key accomplishments.

For **sitrep** reports, just snapshot the current active
thread state.

### Step 5: Save the Report

Save the report to the worklog repository:

```bash
# Standup reports.
# Path: reports/standup-YYYY-MM-DD.md

# Weekly reports.
# Path: reports/weekly-YYYY-WNN.md

# Monthly reports.
# Path: reports/monthly-YYYY-MM.md

# Quarterly reports.
# Path: reports/quarterly-YYYY-QN.md

# Custom reports.
# Path: reports/custom-YYYY-MM-DD-to-YYYY-MM-DD.md

# Sitrep snapshots.
# Path: sitreps/YYYY-MM-DDTHH-MM.md
```

### Step 6: Commit

Stage only the paths that were created or modified, then
commit with sign-off:

```bash
git -C <worklog-path> add <modified-paths...>
git -C <worklog-path> commit -s -m \
    "worklog: report — <type> <date-range>"
```

Replace `<modified-paths...>` with the specific files or
directories that changed. Do not use broad staging commands
such as `git add -A` or `git add .`.

### Step 7: Present

Display the report to Cesar. For standup reports, also
offer to copy it to clipboard or format it for Slack.

## Cross-Checking with Codex

For **quarterly** reports (which may be used for
performance reviews), cross-check the report with Codex
using the `consult-codex` skill.
Ask Codex to:
- Verify the statistics are accurate.
- Suggest any missing accomplishments.
- Improve the phrasing of key accomplishments.

This is optional for other report types.

## Tips

- Reports are generated from worklog data, not live
  sources. Run `/sitrep` first if you want up-to-date data
  before generating a report.
- The standup format should fit in a Slack message or a
  2-minute verbal update. Keep it brief.
- The quarterly format emphasizes impact and themes over
  individual task details — it is designed for performance
  review discussions.
- Prefer `wl thread list` and `wl thread meta` over
  `wl thread get` when scanning many threads. Only read
  full thread content for items that need detailed activity
  log extraction (e.g., key accomplishments for quarterly
  reports).
- Keep current-state statistics separate from historical
  date-range statistics. `wl summary stats` reports both;
  do not conflate them in the report narrative.
- Report files are committed to the worklog repo for
  historical reference. Previous reports can be useful
  input for future quarterly summaries.

## Constraints

- All report data comes from the worklog repository via the
  `wl` tool. Do not query live notification sources — that
  is the sitrep's job.
- Reports are read-only artifacts. They do not modify
  worklog threads or state.
- Commit report files to the worklog repo after generating
  them.

## Target

$ARGUMENTS
