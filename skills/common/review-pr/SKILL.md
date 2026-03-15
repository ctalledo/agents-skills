---
name: review-pr
description: >-
  Review a GitHub pull request. Accepts a PR URL, owner/repo#N, #N, or bare
  number. Analyzes correctness, design, testing, and CI state, then prepares a
  findings-first report and draft inline comments. Waits for user direction
  before posting anything to GitHub.
argument-hint: <PR>
compatibility: >-
  Requires gh (GitHub CLI) authenticated with repo scope. Reading CI details
  may also require workflow scope.
---

# Review PR

Review a GitHub pull request and prepare a high-signal review for the user. The
default outcome is a report, including a recommended action (comment, request
changes, or approve) and draft comments, not a posted GitHub review.

The command examples below are recommended starting points, not a fixed
recipe. Adapt them to the repository, the PR's shape, the installed tool
versions, and any better repo-local tooling you discover.

## Autonomous operation

If running as an autonomous subagent, this section overrides the interactive
approval/wait instructions in the procedure below. Skip step 5 (the posting
confirmation step) entirely. Do not post anything to GitHub — no reviews, no
comments, no approvals. Return the complete findings report as your final
output.

## Procedure

### 1. Authenticate and resolve the pull request

Run `gh auth status` first. If authentication fails, stop and ask the user to
authenticate before proceeding.

Parse `$ARGUMENTS` to identify the PR. Supported formats:

- Full URL: `https://github.com/owner/repo/pull/123`
- Qualified: `owner/repo#123`
- Local: `#123` or `123`, resolved against the current repository

If the target repository differs from the current working directory, switch
into the correct repository context or pass `--repo owner/repo` to `gh`
commands.

Fetch the initial PR metadata:

```
gh pr view <PR> --json \
  number,title,body,author,state,baseRefName,headRefName,\
  isDraft,mergeable,mergeStateStatus,reviewDecision,\
  headRefOid,url
```

If the PR cannot be resolved, report the error and stop.

If `state` is `closed` or `merged`, report that to the user and stop unless
they explicitly asked for a retrospective review of a closed PR.

### 2. Gather context

Useful starting queries include the following, and can be run in parallel
where useful:

- **Diff**: `gh pr diff <PR>`
- **Changed file list**: `gh pr diff <PR> --name-only`
- **CI checks**:
  `gh pr checks <PR> --json name,state,bucket,link`
- **Reviews**:
  `gh api repos/{owner}/{repo}/pulls/{number}/reviews`
- **Review comments**:
  `gh api repos/{owner}/{repo}/pulls/{number}/comments`
- **Issue comments**:
  `gh api repos/{owner}/{repo}/issues/{number}/comments`

If the PR has a long review history, use `--paginate` or equivalent
pagination so you do not miss older reviews or comments.

Read the PR description carefully, but treat the current diff and code as the
source of truth if the description appears stale.

If the repository has contribution guides, style guides, or CI configuration
that materially affect the review, read those too.

If `gh pr checks --json` rejects a field name, retry with the fields supported
by the installed `gh` version rather than failing the entire review.

If the PR is large or noisy, start with the changed file list and focus on the
highest-signal files first.

If loading the full diff would be too noisy or too large, inspect selected
files individually instead of dumping the entire diff at once.

Vendored code, generated code, lockfiles, and similar machine-produced
artifacts usually should not be reviewed in depth unless they contain
project-owned logic, security-sensitive behavior, or the user explicitly wants
them reviewed.

Note any areas you did not inspect deeply.

### 3. Analyze the pull request

Perform a holistic review, but only raise findings that materially matter.
Suppress cosmetic or trivial objections that do not affect correctness,
security, testing, or maintainability.

If you suppress minor observations because they are not worth posting, you can
mention them in the private report to the user when useful, but do not include
them in draft review comments by default.

Check at least these areas:

- **Correctness and logic.**
- **Design and architecture.**
- **Security and data handling.**
- **Testing and edge-case coverage.**
- **CI and check status.**
- **Readability and project conventions.**
- **PR hygiene** such as scope creep or a misleading description.

Before drafting a comment, check whether the same issue was already raised in
an existing review or discussion. Avoid duplicate comments unless the PR still
fails to address the concern.

When the evidence is incomplete, say so. Do not overstate certainty.

### 4. Prepare the review report

Present findings to the user in a findings-first structure. Order findings by
severity and include file references whenever possible.

Use this shape:

```
## Review: <PR title> (<PR URL>)

**Author:** @<author>
**Base:** <base> <- <head>
**Status:** <draft|ready> | checks <passing|failing|pending>
**Review decision:** <approved|changes_requested|review_required|none>

### Findings
- [path:line] <severity> - <issue and why it matters>
  Suggested fix: <brief fix or rationale>

### Open questions / assumptions
- <anything you could not verify or that needs clarification>

### Recommendation
- <Approve | Request changes | Comment>
  <brief justification>

### CI snapshot
- <check name>: <pass|fail|pending> (<link>)

### Positive observations
- <things done well, if any>

### Draft inline comments
- <path:line> -> <comment body>

### Brief summary
- <1-3 sentences on what the PR does and overall quality>
```

If there are no material findings, say that explicitly and mention any
residual risk or unverified areas instead of inventing weak comments.

Keep the proposed inline comments concise. One issue per comment.

Write draft comments in a kind, constructive tone. Avoid passive-aggressive or
confrontational phrasing. Prefer concrete suggestions over challenging
questions. Including positive observations in the posted review is fine and
even encouraged (within reason - don't wax poetic), but they should just be
included in the main review body, not as inline comments (which would be too
noisy).

### 5. Confirm the posting plan

After presenting the report, ask the user how to proceed:

- **Post as-is**: Submit the review with the drafted action and comments.
- **Revise**: Edit the recommendation or specific comments before posting.
- **Adjust tone**: Keep the substance, but change the action or wording.
- **Abort**: Do not post anything.

Do not post anything to GitHub until the user gives explicit direction.

### 6. Post the review

If the user approves posting, re-fetch the head SHA immediately before sending
the review. If it changed since the analysis, warn the user and refresh the
review first.

Submit the review atomically so the body and inline comments land together:

```
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST --input <review-payload>.json
```

The payload should include the current `headRefOid`, the review body,
the requested event, and any inline comments.

If a finding does not cleanly map to a commentable diff line, convert it to a
note in the review body rather than silently moving it to a nearby line.

When an inline suggestion is appropriate, use GitHub suggestion
blocks in the comment body.

After posting, confirm success and provide the resulting review URL.

### 7. Clean up

Remove temporary files created for the review, such as JSON payload files. If
you created a worktree only for local inspection, clean it up after use.

## Tips

- Read the full diff before raising a concern. Do not flag an issue that is
  already addressed elsewhere in the PR.
- For large PRs, organize your analysis by risk area or file group rather than
  by diff order.
- If a local checkout would materially improve the review, consider using a
  worktree so you do not disturb the current working directory.
- Keep inline comments short. Reserve broader context for the review body.

## Constraints

- All GitHub interaction must go through the `gh` CLI.
- Never post reviews, comments, or approvals without explicit user direction.
- Do not modify the PR branch as part of this skill unless the user changes the
  task from review to implementation.
- Probing and analysis are fine without permission. Any visible GitHub action
  requires user consent.

## Target

$ARGUMENTS
