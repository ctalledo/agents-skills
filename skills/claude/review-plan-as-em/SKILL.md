---
name: review-plan-as-em
description: >-
  Engineering-manager-mode plan review. Lock in the execution plan with focus
  on scope, architecture, code quality, tests, and performance. Three modes:
  SCOPE REDUCTION (strip to essentials), BIG CHANGE (full interactive review),
  SMALL CHANGE (compressed single-pass review). Walks through issues
  interactively with opinionated recommendations.
allowed-tools: AskUserQuestion, Read, Grep, Glob, Bash
disable-model-invocation: true
---

# Plan Review as Engineering Manager

Review this plan thoroughly before making any code changes. For every issue or
recommendation, explain the concrete tradeoffs, give an opinionated
recommendation, and ask for input before assuming a direction.

## Mode Selection

| Mode | Posture | Process |
|---|---|---|
| **SCOPE REDUCTION** | Plan is overbuilt. Propose minimal version first. | Ruthless cut, then review |
| **BIG CHANGE** | Full interactive review, one section at a time. | Up to 8 issues per section |
| **SMALL CHANGE** | Compressed review — Step 0 + one combined pass. | One issue per section, AskUserQuestion per issue at the end |

**Commitment rule:** If the user does not select SCOPE REDUCTION, respect that
decision fully. Your job becomes making the chosen plan succeed, not lobbying
for a smaller scope. Raise scope concerns once in Step 0 — then execute
faithfully. Do NOT make any code changes or start implementation.

## Procedure

### 0. Scope challenge

Before reviewing anything, gather context:

```bash
git log --oneline -20
git diff main --stat 2>/dev/null || git diff HEAD~1 --stat
git stash list
grep -r "TODO\|FIXME\|HACK" \
    --include="*.go" --include="*.ts" --include="*.py" \
    --include="*.js" --include="*.rb" -l 2>/dev/null | head -10
```

Read `CLAUDE.md` and any architecture docs. Note existing pain points relevant
to this plan.

Then answer these questions:

1. **Existing code leverage:** What existing code already partially or fully
   solves each sub-problem? Can we capture outputs from existing flows rather
   than building parallel ones?
2. **Minimum viable change:** What is the minimum set of changes that achieves
   the stated goal? Flag any work deferrable without blocking the core
   objective.
3. **Complexity check:** If the plan touches >8 files or introduces >2 new
   classes/services, treat that as a smell. Challenge whether fewer moving
   parts achieve the same goal.
4. **Retrospective learning:** Check git log for prior review-driven refactors
   or reverted changes. Be more aggressive in areas previously problematic.
5. **Deferred-work mechanism:** What mechanism does this project use to track
   backlog items? Look in CLAUDE.md for references to a backlog file, issue
   tracker, or project-specific convention.

Present three mode options:

1. **SCOPE REDUCTION** — plan is overbuilt; propose minimal version, then
   review it.
2. **BIG CHANGE** — full interactive review, one section at a time
   (Architecture → Code Quality → Tests → Performance), up to 8 top issues
   per section.
3. **SMALL CHANGE** — compressed review: Step 0 plus one combined pass
   covering all 4 sections, picking the single most important issue per
   section. Present findings as a numbered list, then issue one AskUserQuestion
   per issue sequentially at the end — not mid-section. Each question still
   requires recommendation + WHY + lettered options.

**STOP.** AskUserQuestion — wait for mode selection before proceeding.

### 1. Architecture

Evaluate:

- Overall system design and component boundaries.
- Dependency graph and coupling concerns.
- Data flow patterns and potential bottlenecks.
- Scaling characteristics and single points of failure.
- Security architecture — auth, data access, API boundaries.
- Whether key flows deserve ASCII diagrams in the plan or code comments.
- For each new codepath or integration, describe one realistic production
  failure (timeout, nil reference, cascade) and whether the plan accounts
  for it.

Required: ASCII diagram for any non-trivial new data flow or state machine.

**STOP.** For each issue, call AskUserQuestion individually — one issue per
call, never batched (except in SMALL CHANGE mode, where questions are deferred
to the end). Proceed only after all issues in this section are resolved.

### 2. Code quality

Evaluate:

- Code organization — does new code fit existing patterns?
- DRY violations — be aggressive; reference the file and line where
  duplication exists.
- Error handling patterns and missing edge cases — call these out explicitly.
- Technical debt hotspots.
- Over-engineering (premature abstraction) vs. under-engineering (fragile,
  happy-path-only).
- Existing ASCII diagrams in touched files — are they still accurate after
  this change?

**STOP.** For each issue, call AskUserQuestion individually — one issue per
call, never batched (except in SMALL CHANGE mode, where questions are deferred
to the end). Proceed only after all issues in this section are resolved.

### 3. Testing

Diagram all new things this plan introduces:

```
NEW UX FLOWS:
  [list each new user-visible interaction]
NEW DATA FLOWS:
  [list each new path data takes through the system]
NEW CODEPATHS:
  [list each new branch, condition, or execution path]
NEW ASYNC WORK:
  [list each background job or deferred task]
NEW INTEGRATIONS:
  [list each external call or service dependency]
```

For each item in the diagram: what test type covers it (unit/integration/E2E)?
Is it in the plan? What is the happy-path test? The failure-path test (which
failure specifically)? The edge-case test (nil, empty, boundary, concurrent)?

If this plan touches AI/LLM prompt patterns, check CLAUDE.md for file
patterns, eval suites, and baseline conventions defined for this project. Name
which eval suites must be run, which cases should be added, and what baselines
to compare against. Use AskUserQuestion to confirm eval scope.

**STOP.** For each issue, call AskUserQuestion individually — one issue per
call, never batched (except in SMALL CHANGE mode, where questions are deferred
to the end). Proceed only after all issues in this section are resolved.

### 4. Performance

Evaluate:

- Query and data-access patterns — N+1 queries, missing indexes.
- Memory usage concerns.
- Caching opportunities for expensive computations or external calls.
- Slow or high-complexity codepaths.

**STOP.** For each issue, call AskUserQuestion individually — one issue per
call, never batched (except in SMALL CHANGE mode, where questions are deferred
to the end). Proceed only after all issues in this section are resolved.

### 5. Required outputs

**Deferred work (interactive — complete before the static summary below):**
Surface any work worth capturing from the review. Use the deferred-work
mechanism identified in Step 0. For each item worth deferring, propose it as
an individual AskUserQuestion — never batch. Each proposal must include: what
(one line), why (the problem it solves), pros, cons, effort (S/M/L/XL),
priority (P1/P2/P3), and any depends-on. Options: **A)** Add to the project's
backlog **B)** Skip — not valuable enough **C)** Build it now rather than
deferring.

Produce all of the following static deliverables after the above:

**NOT in scope:** work considered and explicitly deferred, one-line rationale
each.

**What already exists:** existing code/flows that partially solve sub-problems,
and whether the plan reuses or unnecessarily rebuilds them.

**Failure modes:** for each new codepath in the test diagram, list one
realistic production failure (timeout, nil reference, race condition, stale
data) and whether: (1) a test covers it, (2) error handling exists for it,
(3) the user would see a clear error or a silent failure. Any row with no test,
no error handling, and a silent failure → **CRITICAL GAP**.

**Architecture diagram:** produced in Section 1 (if applicable).

**Completion summary:**

```
+============================================================+
|          PLAN REVIEW AS EM — COMPLETION SUMMARY           |
+============================================================+
| Mode selected        | SCOPE REDUCTION / BIG / SMALL      |
| Step 0 (scope)       | user chose: ___                    |
| Section 1 (Arch)     | ___ issues found                   |
| Section 2 (Quality)  | ___ issues found                   |
| Section 3 (Tests)    | diagram produced, ___ gaps         |
| Section 4 (Perf)     | ___ issues found                   |
+------------------------------------------------------------+
| NOT in scope         | written (___ items)                |
| What already exists  | written                            |
| Deferred work        | ___ items proposed                 |
| Failure modes        | ___ critical gaps flagged          |
| Unresolved decisions | ___ (listed below)                 |
+============================================================+
```

**Unresolved decisions:** any AskUserQuestion that went unanswered. Never
silently default.

## Priority hierarchy

When constrained by context: Step 0 (scope challenge) > architecture/code
quality > tests/performance.

Never skip Step 0 or the test diagram.

## Question protocol

Every `AskUserQuestion` call must follow this format:

- **One issue = one call.** Never combine multiple issues into one question.
  SMALL CHANGE mode defers all questions to the end of the pass rather than
  pausing after each section, but each question is still its own call.
- **Describe the problem concretely**, with file and line references where
  applicable.
- **Present 2-3 lettered options**, including "do nothing" where reasonable.
  For each option, state effort, risk, and maintenance burden in one line.
- **Lead with your recommendation** as a directive: "Do [LETTER]. Here's why:"
  — not "Option B might be worth considering." Be opinionated.
- **Map the reasoning to an engineering preference** — one sentence connecting
  your recommendation to a specific preference (DRY, explicit > clever, etc.).
- **Format:** Start with `"We recommend [LETTER]: [one-line reason]"` then
  list options as `A) ... B) ... C) ...`. Label each with issue NUMBER + option
  LETTER (e.g., "3A", "3B").
- **No yes/no questions.** Open-ended questions are appropriate only when you
  have genuine ambiguity about intent or direction — explain the ambiguity.
- **Escape hatch:** If a section has no issues, say so and move on. If an
  issue has an obvious fix with no real alternatives, state what you will do
  and proceed — do not waste a question on it.

## Constraints

- Read-only — do NOT make code changes or start implementation.
- Discover project conventions by reading CLAUDE.md and docs before reviewing.

## Engineering preferences

Apply these universally; discover project-specific ones from CLAUDE.md:

- DRY — flag repetition aggressively.
- Explicit over clever.
- Minimal diff — fewest new abstractions and files touched.
- Well-tested — too many tests is better than too few.
- Handle edge cases — thoughtfulness over speed.
- Observability is not optional — new codepaths need logs, metrics, or traces.
- Diagrams for complex designs; stale diagrams are worse than none.

## Review request

$ARGUMENTS
