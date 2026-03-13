---
name: drive-pr
description: >-
  Drive a GitHub pull request toward completion. Assesses current state,
  identifies blockers, recommends the next high-leverage action, and then
  executes approved follow-up work. For own PRs it can address feedback, fix
  CI, and prepare the PR to merge. For others' PRs it can review, diagnose CI,
  and draft comments or nudges. Uses fix-ci and review-pr when appropriate.
argument-hint: [PR]
disable-model-invocation: true
compatibility: >-
  Requires gh (GitHub CLI) authenticated with repo scope. Reading CI details or
  rerunning workflows may also require workflow scope.
---

# Drive PR

Drive a pull request toward merge by identifying blockers, choosing the next
useful action, and reassessing after each completed step.

Treat this skill as an orchestrator. Prefer handing focused review
work to `review-pr` and focused CI diagnosis to `fix-ci` instead of
duplicating their procedures in full.

The command examples below are recommended starting points, not a fixed
recipe. Adapt them to the repository, the current blocker, the installed tool
versions, and any better local tooling or narrower skills available.

## Procedure

### 1. Authenticate and resolve the pull request

Run `gh auth status` first. If authentication fails, stop and ask the user to
authenticate before proceeding.

Parse `$ARGUMENTS` as one of:

- Full URL: `https://github.com/owner/repo/pull/123`
- Qualified: `owner/repo#123`
- Local: `#123` or `123`

If the target repository differs from the current working directory, switch
into the correct repository context or pass `--repo owner/repo` to `gh`
commands.

If no argument is provided, use the PR for the current branch:

```
gh pr view --json number,url
```

Fetch PR metadata:

```
gh pr view <PR> --json \
  number,title,body,author,state,baseRefName,headRefName,\
  isDraft,mergeable,mergeStateStatus,reviewDecision,\
  statusCheckRollup,url,createdAt,updatedAt,\
  reviewRequests,assignees,isCrossRepository,\
  maintainerCanModify,headRefOid
```

If the PR cannot be resolved, report the error and stop.

If `state` is `closed` or `merged`, report that to the user and stop unless
they explicitly want post-merge follow-up or retrospective analysis.

### 2. Determine what actions are possible

Identify the authenticated user:

```
gh api user --jq .login
```

Compare that login with the PR author and note whether the PR comes
from an external fork.

Use this to classify what is realistically possible:

- **Own PR**: You can usually make local fixes and may be able to push,
  resolve threads, mark ready, or merge.
- **Someone else's PR**: You can review, diagnose CI, draft comments, and only
  push if repository permissions and branch settings allow it.
- **Cross-repository PR without maintainer edits**: Treat code changes as
  advisory unless the user provides another path.

Do not assume push or merge rights from authorship alone. Verify permissions
before any remote write.

### 3. Assess the PR state

Useful starting queries include the following, and can be run in parallel
where useful:

- **CI status**:
  `gh pr checks <PR> --json name,state,bucket,link`
- **Reviews**:
  `gh api repos/{owner}/{repo}/pulls/{number}/reviews`
- **Review threads**:
  use GraphQL if you need resolution state or thread metadata
- **Issue comments**:
  `gh api repos/{owner}/{repo}/issues/{number}/comments`

Use pagination when needed. Do not assume the first page of reviews, issue
comments, or review threads is complete.

If `gh pr checks --json` rejects a field name, retry with the fields supported
by the installed `gh` version rather than failing the whole assessment.

Evaluate the main blockers:

- Is the PR still a draft?
- Are checks failing or still pending?
- Is the review decision blocking?
- Are there unresolved review threads?
- Are there merge conflicts?
- Is the PR stale or waiting on another person?

Only claim a blocker when you have evidence for it. If branch-protection or
merge-queue requirements are not directly visible, describe them as possible
constraints rather than facts.

### 4. Present the assessment

Summarize the current state and recommend the next highest-leverage action.
Prefer a short, prioritized list over an exhaustive inventory.

Use a structure like this:

```
## PR Status: <title> (<URL>)

**Author:** @<author>
**Yours:** <yes|no>
**State:** <open|draft>
**Mergeability:** <mergeable|conflicting|unknown>
**Review decision:** <approved|changes_requested|review_required|none>

### Blocking items
1. <blocker>
2. <blocker>

### Recommended next action
1. <best next step>

### Secondary actions
1. <optional follow-up>
2. <optional follow-up>
```

After presenting the assessment, ask the user which action to take. Prefer one
approved action at a time, then reassess.

### 5. Execute the approved action

Only execute actions the user explicitly approves.

Before any visible or mutating action, refresh the current PR state so you are
not acting on stale checks, reviews, or mergeability. If anything material
changed, update the plan first.

Common actions:

#### Fix failing CI

Invoke `fix-ci` when checks are failing and the problem needs diagnosis or a
targeted repair.

If `fix-ci` is unavailable, do a smaller version of that workflow
here: inspect the failing run, identify the likely root cause, and
bring the diagnosis back to the user before changing anything.

#### Review the PR

Invoke `review-pr` when the user wants a formal review, when you need
a findings-first assessment before acting, or when a substantial
local fix should be self-reviewed before it is pushed.

#### Address review feedback

For each unresolved thread the user wants to handle:

1. Read the thread and the relevant code.
2. Decide whether the right move is to change code, reply with rationale,
   ask a question, or defer.
3. Present that plan to the user and wait for approval before making code
   changes or posting any reply.
4. Post the reply via the REST API. Use the top-level review comment ID for the
   comment being replied to, not the review-thread node ID:
   ```
   gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
     --method POST -f body="<response>"
   ```
5. Only resolve the thread after the fix or explanation is in place.
   Use the review-thread node ID for the GraphQL mutation:
   ```
   gh api graphql -f query='
     mutation($id:ID!) {
       resolveReviewThread(input:{threadId:$id}) {
         thread { isResolved }
       }
     }' -f id=<thread-node-id>
   ```

If the approved change set is substantial, run `review-pr` as a self-review
before any remote update.

#### Resolve merge conflicts

If the PR has merge conflicts, ask whether the project expects a rebase or a
merge-based update. Do not assume one strategy.

Run the approved strategy as separate steps, not a chained shell command:

```
git fetch origin <base>
git rebase origin/<base>
```

or:

```
git fetch origin <base>
git merge origin/<base>
```

Present the result to the user before pushing.

#### Draft or post a nudge

If the PR is waiting on another person, draft a short comment for the user to
approve before posting. Keep nudges polite, specific, and low-pressure.

#### Mark ready or merge

Only consider these after blockers are cleared and the user asks for them
explicitly.

For merge, confirm the desired strategy first:

```
gh pr merge <PR> --squash
gh pr merge <PR> --merge
gh pr merge <PR> --rebase
```

### 6. Reassess and report

After completing an approved action, reassess the PR state and summarize:

```
## Actions taken
- <action>: <result>

## Remaining blockers
- <anything still blocking>

## Recommended next step
- <best follow-up action>
```

If one or two action cycles do not improve the PR's state, stop and surface
the remaining blocker to the user instead of looping indefinitely.

## Tips

- Focus on the highest-leverage blocker first.
- When a PR belongs to someone else, default to advisory help unless the user
  explicitly wants you to act on their behalf and the platform permits it.
- Keep PR-driving work incremental. Large batches of actions are harder to
  verify and harder to explain.

## Constraints

- All GitHub interaction must go through the `gh` CLI.
- Never post comments, reply to threads, rerun CI, mark ready, merge,
  commit, or push without explicit user direction.
- Do not assume permission to push to someone else's branch just
  because maintainer edits might be enabled. Check repository
  permission before any remote write, for example with:
  `gh repo view --json viewerPermission --jq .viewerPermission`.
- Prefer one approved action at a time, then reassess.
- Probing and analysis are fine without permission. Mutations require user
  consent.

## Target

$ARGUMENTS
