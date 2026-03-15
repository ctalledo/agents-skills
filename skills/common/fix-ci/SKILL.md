---
name: fix-ci
description: >-
  Debug and fix failing CI checks on a GitHub branch or pull request. Inspects
  check status via gh, fetches logs, diagnoses root causes, and presents
  findings plus concrete next actions. Works with the user to drive resolution
  and can be used directly or as support for drive-pr.
argument-hint: [PR-or-branch]
compatibility: >-
  Requires gh (GitHub CLI) authenticated with repo scope. Reading CI details or
  rerunning workflows may also require workflow scope.
---

# Fix CI

Diagnose failing CI on a branch or pull request. Start with inspection and
explanation. Only modify files, rerun workflows, commit, or push after the
user explicitly approves those actions.

The command examples below are recommended starting points, not a fixed
recipe. Use other read-only commands, helper scripts, or repo-specific tooling
when they are a better fit for the failure at hand. If you need to widen the
investigation beyond routine read-only probing, confirm with the user first.

## Autonomous operation

If running as an autonomous subagent, this section overrides the interactive
approval/wait instructions in the procedure below. Skip all approval gates:
proceed directly from diagnosis through local code fixes without pausing to
ask for permission. Stop before committing or pushing — do not run
`git commit`, `git push`, or any equivalent remote-write operation.

Return a structured summary of findings and changes when done (see the
`ci-fixer` agent definition for the exact format).

## Procedure

### 1. Authenticate and resolve the target

Run `gh auth status` first. If authentication fails, stop and ask the user to
authenticate before proceeding.

If `$ARGUMENTS` is provided, parse it as one of:

- Full URL: `https://github.com/owner/repo/pull/123`
- Qualified PR: `owner/repo#123`
- Local PR: `#123` or `123`
- Branch name, resolved against the current repository

If the target repository differs from the current working directory, switch
into the correct repository context or pass `--repo owner/repo` to `gh`
commands.

If no argument is given, prefer the PR for the current branch:

```
gh pr view --json number,url 2>/dev/null
```

If there is no current-branch PR, fall back to the current branch name and use
its workflow runs:

```
git branch --show-current
```

If you cannot resolve either a PR or a branch, report the problem and stop.

### 2. Collect check and run state

Useful starting commands include the following for collecting current check and
run state.

For a PR:

```
gh pr checks <PR> --json name,state,bucket,link
```

If `gh` rejects a field name, retry with the fields supported by the installed
version instead of failing outright.

For a branch without a PR, fetch recent workflow runs:

```
gh run list --branch <branch> \
  --json databaseId,name,status,conclusion,url --limit 20
```

Categorize each item as:

- **Passing**: No action needed.
- **Failing**: Needs diagnosis.
- **Pending / running**: Note and monitor.
- **Cancelled / skipped**: Mention if unexpected.

If everything is passing, report that status and stop.

### 3. Diagnose each failure

Investigate failing checks one by one. Independent checks can be diagnosed in
parallel when that helps.

For GitHub Actions checks:

1. Identify the run ID from the check URL or `databaseId`.
2. Fetch run metadata:
   ```
   gh run view <run_id> --json \
     name,workflowName,conclusion,status,jobs,url
   ```
3. Fetch failed-job logs:
   ```
   gh run view <run_id> --log-failed
   ```
4. If that is not enough, fetch full logs:
   ```
   gh run view <run_id> --log
   ```
5. Isolate the failing job, step, and concrete error.

If the repository or current environment already provides a helper script for
inspecting checks or summarizing logs, prefer it when it is clearly a better
fit than raw `gh` commands.

Do not dump full logs into the conversation unless absolutely
necessary. Quote or summarize only the relevant step or the last
useful lines around the failure.

Read the code or test files referenced in the logs when that will
sharpen the diagnosis.

Attempt to reproduce the failure locally when feasible, safe, and useful.
Skip it or ask the user first if reproduction would run destructive
commands, require elevated privileges, or execute obviously risky project
scripts.

Classify each failure into one of these buckets:

- **Code error**: Test, build, lint, or type failure caused by the code.
- **Flaky test**: Intermittent test failure or timeout.
- **Configuration issue**: Broken workflow logic, permissions, or secrets.
- **Infrastructure issue**: Runner, resource, network, or dependency problems.
- **Platform issue**: A wider outage or provider-side incident.
- **Unknown**: Not enough evidence yet.

For external CI providers, do not attempt to scrape provider logs. Report the
check name, the external URL, and the limit of what you can infer locally.

### 4. Check for broader outages

If the symptoms suggest infrastructure or provider trouble rather than a code
regression, call that out explicitly.

If status-page checks are possible in the current environment,
inspect the relevant status page and summarize anything active.
Otherwise, provide the URL for the user to verify manually.
The primary GitHub status page is https://www.githubstatus.com/.

Avoid overstating confidence. "Likely infrastructure issue" is better than a
definite claim with weak evidence.

### 5. Present findings and options

Present the diagnosis in a compact, check-by-check format:

```
## CI Diagnosis: <PR or branch identifier>

### <check-name>: <failure-type>
**Run:** <URL>
**Job:** <job-name> | **Step:** <step-name>
**Evidence:** <short log excerpt or summary>
**Diagnosis:** <root cause explanation>
**Suggested next action:** <specific action>
```

Group code errors first, then flaky tests, then configuration or
infrastructure issues.

After presenting the findings, offer concrete next actions:

- **Make a local fix** for a code or configuration error.
- **Rerun one or more workflows** if the evidence points to flakiness.
- **Wait and monitor** if there is a likely outage.
- **Investigate further** if the diagnosis is still weak.
- **Stop** if the user only wanted the diagnosis.

Call out missing or incomplete logs explicitly so the user understands when the
diagnosis is limited by the available evidence.

If diagnosis confidence is low, present multiple plausible causes instead of
asserting a single root cause.

Be explicit that a successful rerun can confirm flakiness, but it does not fix
the underlying issue by itself.

### 6. Execute the approved action

Wait for explicit user approval before making any code changes, rerunning
workflows, committing, or pushing.

If the user approves a local fix:

1. Make the smallest change that addresses the diagnosed failure.
2. Verify locally when practical, such as by running the failing test or
   lint command.
3. Present the result and any remaining uncertainty to the user.
4. Only commit or push if the user explicitly asks for that and the
   repository rules allow it.

If the user approves a rerun:

```
gh run rerun <run_id>
```

or, when appropriate:

```
gh run rerun <run_id> --failed
```

If you watch the rerun, use a reasonable stopping point rather than waiting
forever. If the run stalls well past its normal duration, stop watching and
report the current status to the user.

If one round of fixing or rerunning does not resolve the failure,
re-diagnose once. If a second round also fails, stop iterating and
ask the user how to proceed.

### 7. Confirm the current state

After the approved action completes, re-check the current status:

```
gh pr checks <PR>
```

or the equivalent run list for a branch target.

Report what is now passing, still failing, or still pending. If anything
remains broken, ask the user whether to continue or stop.

## Tips

- Read the test code and the code under test when logs alone are ambiguous.
- Prefer minimal, targeted changes. CI repair is not a license to refactor.
- If landing the fix remotely matters, verify repository permission and
  branch ownership before attempting to push. A quick repository check is:
  `gh repo view --json viewerPermission --jq .viewerPermission`.
- A worktree can be useful when you need to inspect or test a PR branch
  without disturbing the current directory.

## Constraints

- All GitHub interaction must go through the `gh` CLI.
- Do not modify files, rerun workflows, commit, or push without explicit user
  direction.
- Do not assume push access. Verify permissions before any remote write.
- Do not rely on external CI provider UIs unless the task explicitly expands
  to them.
- Probing and analysis are fine without permission. Mutations require user
  consent.

## Target

$ARGUMENTS
