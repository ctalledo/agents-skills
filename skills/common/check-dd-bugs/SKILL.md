---
name: check-dd-bugs
description: >-
  Fetch open Docker Desktop bugs from docker/for-mac and docker/for-win opened
  in the last 4 months and present them as a single table sorted by activity
  (comment count descending, then most recent comment first).
compatibility: >-
  Requires gh (GitHub CLI) authenticated with repo scope.
---

# Check Docker Desktop Bugs

Fetch open issues from `docker/for-mac` and `docker/for-win` opened in
the last 4 months and display them as a single merged table, most active
first.

## Procedure

### 1. Compute the cutoff date

Compute the ISO timestamp for 4 months ago (try macOS `date -v` syntax
first, fall back to GNU `date -d`):

```bash
cutoff=$(date -v-4m +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d '4 months ago' +%Y-%m-%dT00:00:00Z)
```

### 2. Fetch open issues from both repos

Compute a secondary cutoff for the stale-silent filter: 2 months ago.

```bash
stale=$(date -v-2m +%Y-%m-%dT00:00:00Z 2>/dev/null \
  || date -d '2 months ago' +%Y-%m-%dT00:00:00Z)
```

Run both commands in parallel. Each command returns a JSON array of
objects with `repo`, `number`, `title`, `createdAt`, and `comments`
(the comment count, not the comment objects). Exclude issues that have
zero comments **and** were opened more than 2 months ago — they are
stale with no engagement and would only add noise.

```bash
gh issue list -R docker/for-mac --state open \
  --json number,title,createdAt,comments --limit 200 \
  | jq --arg cutoff "$cutoff" --arg stale "$stale" \
    '[.[] | select(.createdAt >= $cutoff)
      | {repo: "for-mac", number, title, createdAt,
         comments: (.comments | length)}
      | select(.comments > 0 or .createdAt >= $stale)]'

gh issue list -R docker/for-win --state open \
  --json number,title,createdAt,comments --limit 200 \
  | jq --arg cutoff "$cutoff" --arg stale "$stale" \
    '[.[] | select(.createdAt >= $cutoff)
      | {repo: "for-win", number, title, createdAt,
         comments: (.comments | length)}
      | select(.comments > 0 or .createdAt >= $stale)]'
```

Merge both arrays into a single list.

### 3. Fetch last comment date for issues with comments

For each issue where `comments > 0`, fetch the date of the most recent
comment. Use `per_page=100` (sufficient for bug reports of this age):

```bash
gh api \
  "repos/docker/<repo>/issues/<number>/comments?per_page=100" \
  --jq '.[-1].created_at'
```

Run these fetches in parallel where possible. For issues with
`comments == 0`, set `lastCommentAt` to `null`.

### 4. Sort and present

Sort the merged list by:
1. `comments` descending (most comments first).
2. `lastCommentAt` descending (most recent comment first) — issues with
   no comments sort after all commented issues.
3. `createdAt` descending as a tiebreaker.

Present the result as a single Markdown table with these columns:

| Issue | Comments | Opened | Last Comment | Title |

- **Issue**: a Markdown link using the issue number as the label and
  `https://github.com/docker/<repo>/issues/<number>` as the URL, e.g.
  `[for-mac#7849](https://github.com/docker/for-mac/issues/7849)`.
- **Comments**: the integer comment count.
- **Opened**: human-readable relative date (e.g. "today", "yesterday",
  "3 days ago", "2 weeks ago", "last month", "2 months ago").
- **Last Comment**: same human-readable format, or "—" if no comments.
- **Title**: the issue title, truncated to ~70 characters if needed.

## Tips

- Parallelize the per-issue comment fetches (step 3) to keep total
  run time under a few seconds for typical volumes (~50 issues).
- If either `gh issue list` call fails (e.g. auth or rate limit),
  report the error and present results from the remaining repo rather
  than aborting entirely.
- The 4-month fetch window combined with the stale-silent filter (drop
  zero-comment issues older than 2 months) keeps the list focused on
  issues that have either recent activity or recent filing.

## Constraints

- Read-only. Do not post, close, label, or otherwise mutate any issue.
- All GitHub interaction must go through the `gh` CLI.
