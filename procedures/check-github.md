# Check GitHub Procedure

This procedure checks GitHub for actionable notifications
and PR activity. It is run as a forked subagent by the
sitrep and concierge skills.

The command examples below are recommended starting points.
Adapt queries, pagination, and field selections to the
volume and shape of the data you encounter.

## Configuration

Read these values from the worklog config:

```bash
# GitHub user, repos, teams, and ignored authors from
# config/sources.yaml.
# github.user
# github.repos
# github.teams[].org
# github.teams[].slug
# github.ignored_authors
#
# Weekend-aware review deadline settings from
# config/preferences.yaml.
# business_time.timezone
# business_time.exclude_weekends
# thresholds.pr_review_overdue_hours
# thresholds.own_pr_review_overdue_hours
```

The `repos` list scopes **all** notification and search
queries to specific repositories. This applies to every
step in this procedure — not just the `/notifications`
API call. Filter out any result whose full repository
name (`owner/repo`) is not in the `repos` list,
regardless of which step produced it.

The `ignored_authors` list contains GitHub usernames whose
activity should not generate worklog threads. When
processing any notification or PR, if the author matches
an entry in `ignored_authors`, do not classify it, do not
include it in findings, and do not create a worklog thread
for it. However, **do** include the notification ID in the
cleanup list so that the notification is still cleaned up
(marked as read). Bot accounts are listed without the
`[bot]` suffix (e.g., `mcp-registry-bot` matches the
GitHub user `mcp-registry-bot[bot]`).

Read the last checkpoint and capture the scan start time:

```bash
wl state checkpoint get github
scan_started_at="$(wl util now --format iso)"
```

If the checkpoint is empty (first run), use a default of
24 hours ago.

## Before Step 1: Initialize the Scan Log

Create the scan log file before issuing any API queries:

```bash
scan_log="$(wl scan init github)"
```

This returns the absolute path to the scan log file. All
enumerated notification IDs and PR refs are written to
this file as `- [ ]` items during Phase 1. Phase 2
classifies them and updates the items to `- [x]` with
labels. The file persists as an audit trail whether or not
the subagent completes successfully.

## Phase 1: Enumerate Items

Enumerate all notification IDs and review-request PR refs
to the scan log before classifying any of them.

### Step 1: Fetch Notifications

Use `gh api` to retrieve notifications since the last
checkpoint. Use `--jq` to extract only the fields needed
and to filter to monitored repos, keeping the response
compact.

```bash
gh api /notifications \
    --method GET \
    -f all=false \
    -f per_page=50 \
    -f since="<CHECKPOINT_TIMESTAMP>" \
    --jq '[.[] | {
        id: .id,
        reason: .reason,
        unread: .unread,
        subject_title: .subject.title,
        subject_type: .subject.type,
        subject_url: .subject.url,
        repo: .repository.full_name,
        updated_at: .updated_at
    } | select(
        .repo == "docker/pinata" or
        .repo == "docker/sysbox-ee" or
        .repo == "nestybox/sysbox"
    )]'
```

Read the repo list from `config/sources.yaml` under
`github.repos` and build the `select()` filter
dynamically using exact `full_name` matches — do not
hardcode the repo names in the jq expression.

#### Pagination

The `/notifications` endpoint returns at most `per_page`
results (max 50). If the response contains exactly
`per_page` items, there may be more pages. Paginate by
incrementing the `page` parameter:

```bash
gh api /notifications \
    --method GET \
    -f all=false \
    -f per_page=50 \
    -f page=2 \
    -f since="<CHECKPOINT_TIMESTAMP>" \
    --jq '...'
```

Continue until a page returns fewer than `per_page` items.

After each page, append each notification to the scan log
as an unchecked `- [ ]` line under `## Items`:

```
- [ ] `notif:<ID>` `<REPO>#<NUMBER>` — <SUBJECT_TITLE> (reason: <REASON>) — (pending)
```

Record the page in `## Pagination Log`:

```
- Page N: M notifications (page: N).
```

### Step 2: Fetch Explicit Review Requests

Notifications alone may miss review requests. Supplement
with targeted PR searches, scoped to the monitored repos.

**Important:** Every `gh search prs` call **must** include
a `--repo=<owner/repo>` flag to restrict results to a
monitored repository. Run one search per repo in
`github.repos`. The `@me` shorthand searches across all
repos the user has access to, so without `--repo` it will
return PRs from unmonitored repos (e.g., personal forks,
upstream open-source projects). Always include `--repo`.

```bash
# PRs awaiting review from my user (per repo).
# Run this once for each repo in github.repos.
gh search prs \
    --review-requested=@me \
    --repo=docker/pinata \
    --state=open \
    --json number,repository,title,url,updatedAt \
    --limit 50

# PRs awaiting review from my teams (per repo).
# For each repo, only run team-scoped searches for
# teams whose org matches the repo owner.
gh search prs \
    --review-requested=docker/app-runtime \
    --repo=docker/pinata \
    --state=open \
    --json number,repository,title,url,updatedAt \
    --limit 50
```

Read the repo list from `config/sources.yaml` under
`github.repos` and the team objects from `github.teams`
— do not hardcode them. Build team-scoped searches as
`<team.org>/<team.slug>`. Only run a team search against
repos whose owner matches `team.org`.

As a safety net, post-filter results: discard any PR
whose full repository name is not in `github.repos`.

Append each new PR ref to the scan log as:

```
- [ ] `pr:<OWNER>/<REPO>#<NUMBER>` — <TITLE> (review-requested) — (pending)
```

After all enumeration is complete, update the scan log
frontmatter:

```bash
yq --front-matter=process \
    '.pagination.pages = N | .pagination.total_items = T | .pagination.phase1_complete = true' \
    -i "$scan_log"
```

## Phase 2: Classify Items

Read the `- [ ]` items from the scan log and classify each
one. Process in batches of 20–30.

### Step 2b: Filter Draft and Closed PRs

For each PR identified as a potential review request in
Steps 1 and 2, check its current state and draft status
before classifying it:

```bash
gh pr view <number> -R <repo> \
    --json isDraft,state \
    --jq '{isDraft, state}'
```

- If `isDraft` is `true`, discard the finding. Draft PRs
  are not ready for review. Do not include them in Action
  Required findings or suggest creating worklog threads.
- If `state` is `MERGED` or `CLOSED`, classify the finding
  as **Completed / Resolved** (not Action Required). If
  there is an existing worklog thread for the PR, include
  it in the completed findings so the caller can propose
  closing it.

Only PRs that are **open and not draft** proceed to the
review checks in Step 3b and the Action Required
classification in Step 4.

### Step 3: Check Own PR Status

Look for feedback on PRs authored by the user, scoped to
the monitored repos. Run one search per repo in
`github.repos`. As with Step 2, always include `--repo`
to prevent results from unmonitored repos leaking in:

```bash
# Run once per repo in github.repos.
gh search prs \
    --author=@me \
    --repo=docker/pinata \
    --state=open \
    --json number,repository,title,url,updatedAt,\
reviewDecision \
    --limit 50
```

For each own PR, note:
- Whether it has new review comments since last check.
- Whether it has been approved.
- Whether it has been open >48 hours with no review
  (overdue — check `config/preferences.yaml` for the
  `thresholds.own_pr_review_overdue_hours` value).

Do **not** use raw wall-clock elapsed hours when
`business_time.exclude_weekends` is true. Instead,
compute the due timestamp with:

```bash
wl util add-weekday-hours <pr-created-at> \
    <threshold-hours> \
    --timezone "<BUSINESS_TIMEZONE>"
```

Then compare the resulting due timestamp against the
current time. This keeps Friday-afternoon PRs from being
treated as overdue on Monday morning just because the
weekend elapsed.

### Step 3b: Check for Already-Submitted Reviews

For each `review_requested` PR that passed the team
filter (i.e., it was requested of my user or one of my
monitored teams), check whether I have already submitted
a review:

```bash
gh pr view <number> -R <repo> \
    --json reviews \
    --jq '[.reviews[] | select(.author.login == "<GITHUB_USER>") | {state, submittedAt}]'
```

Read the username from `github.user` in
`config/sources.yaml`.

If the result contains a review with `state: "APPROVED"`,
compare its `submittedAt` timestamp against the
`updated_at` of the `review_requested` notification that
triggered this check. If the notification is **newer**
than the approval, the author likely pushed new commits
and re-requested review — treat the PR as **Action
Required** (a re-review is needed). If the approval is
newer than or equal to the notification, the review is
complete — classify the PR as **Status Update Only**.

If the result contains reviews with other states
(`COMMENTED`, `CHANGES_REQUESTED`) but no `APPROVED`
review, the review is still in progress and the PR
remains **Action Required**.

Only run this check for PRs that would otherwise be
classified as Action Required. Skip it for PRs that are
already filtered out (wrong team, ignored author, etc.).

When deciding whether an incoming review request is
overdue, use the same weekday-hours calculation with
`thresholds.pr_review_overdue_hours` and the
review-request timestamp (or the best available equivalent
timestamp).

### Step 4: Classify Findings

Organize findings into three categories:

#### Action Required

- Review requests where the review was requested of
  my user (per `github.user` in sources.yaml) or one of
  my monitored team objects (per `github.teams` in
  sources.yaml), and where I have NOT already approved
  the PR, or where a re-review has been requested since
  my approval (see Step 3b). Review requests of other
  teams — even ones I'm a member of — are NOT actionable
  and should be skipped.
- @-mentions requesting my input.
- Feedback on my own PRs that needs addressing.
- Failed CI on my own PRs.

#### Status Update Only

- Merged PRs I was watching.
- Comments that are FYI (no action needed from me).
- CI passing on my own PRs.
- Reviews from others on PRs I'm subscribed to.

#### Completed / Resolved

- PRs that have been merged or closed.
- Issues that have been resolved.
- Notifications for threads that are no longer active.

After classifying each batch, update the scan log items
from `- [ ]` to `- [x]` with the appropriate label
(`**action-required**`, `**status-update**`,
`**completed**`, `**ignored**`, `**cleanup-only**`).

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

Use `status: "partial"` if some batches failed.

## Step 5: Return Structured Findings

Return a single YAML block using the shared findings
schema in `findings-schema.md`.

GitHub-specific requirements:

- Set `source: github`.
- Set `scan_started_at` to the value captured at the start
  of the check.
- Set `scan_log_path` to the worklog-relative path of the
  scan log.
- Put notification IDs in `cleanup.github_notification_ids`.
- Set `proposed_state_updates.checkpoint = scan_started_at`.
- Use canonical `github:<owner>/<repo>#<number>` refs.

Include notification IDs so the caller can mark them as
read after committing worklog updates:

```bash
# Mark a notification as read.
gh api /notifications/threads/<THREAD_ID> \
    --method PATCH
```

## Tips

- Always use `--json` and `--jq` with `gh` commands to
  keep output compact and structured.
- The `subject_url` from notifications is an API URL, not
  a web URL. To get the web URL for a PR, use:
  `gh pr view <number> -R <repo> --json url --jq '.url'`
- If `gh` rejects a `--json` field name, retry with the
  fields supported by the installed version rather than
  failing the entire check.
- For large notification backlogs (e.g., after a vacation),
  complete Phase 1 fully before starting Phase 2. The scan
  log is the handoff point between the two phases.

## Constraints

- All GitHub interaction goes through the `gh` CLI.
- This procedure is read-only: it fetches and classifies
  but does not mark notifications as read or post anything.
  The caller handles cleanup after worklog commit and
  applies the proposed checkpoint afterward.
- The canonical worklog source ref format is
  `github:<owner>/<repo>#<number>`.
- Read repo, team, and ignored-author lists from
  `config/sources.yaml` — do not hardcode them.
