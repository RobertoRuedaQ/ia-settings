---
name: durable-plan
description: |
  Turn a multi-file or multi-session unit of work into a durable, on-disk
  plan that survives context loss (compaction, /clear, a new session, a
  different machine) instead of living only in conversation state. Use when
  a task touches 3+ files, carries explicit acceptance criteria, or is
  clearly going to outlive one sitting — write the spec and task plan to
  disk before writing any code.
  Do NOT use for: a single-file fix, an exploratory/throwaway script, or
  anything you can finish and verify inside the current turn — for that,
  use the built-in plan mode or just do the work. The overhead of a durable
  plan isn't worth it below the 3-file/multi-session bar.
---

# Durable Plan

A plan that only exists in the conversation dies with the conversation. This
skill writes it to disk instead, as two small markdown files that any future
session — yours, a teammate's, a fresh context — can pick up and resume from
without re-deriving anything.

## Where it lives

`docs/plans/<slug>/spec.md` and `docs/plans/<slug>/plan.md`, committed like
any other doc. `<slug>` is a short kebab-case name for the unit of work
(`rate-limit-api`, not `plan-3`). If the repo has its own convention for
in-flight work docs, use that location instead — the two-file shape matters
more than the path.

## Step 1 — Write the spec (the "what")

`spec.md` answers, in this order:

- **Problem** — what's wrong or missing, in one paragraph.
- **Scope** — what this unit of work covers.
- **Out of scope** — what it deliberately does not cover (prevents scope
  creep mid-implementation).
- **Acceptance criteria** — a checklist, and every item must be
  *falsifiable*: something you can point at and say pass/fail, not a vibe.
  - Bad: "rate limiting works."
  - Good: "the 11th request in 60s from one client gets a 429."
- **Constraints** — anything external that shapes the solution (must not
  break X, must ship without a new dependency, must work offline).
- **Open questions** — anything genuinely ambiguous; resolve these before
  locking the spec, don't carry them into implementation as a surprise.

## Step 2 — Stress-test the spec once before locking it

Before moving to the task plan, review the spec for the failure modes that
are cheap to catch now and expensive to catch mid-implementation: vague
acceptance criteria, an unstated assumption, a constraint that contradicts
the scope. If the `skeptic` agent is available, run the spec's acceptance
criteria past it — its job is exactly this: catching a claim ("this
criterion proves the feature works") that doesn't actually hold up. Revise
the spec, don't skip straight to planning around a weak one.

## Step 3 — Write the task plan (the "how")

`plan.md` is an ordered checklist. Every task names its own file set and any
task it depends on, so a fresh session can tell what's safe to work on next
without reading the whole history:

```
- [ ] T1: Add rate-limit middleware — files: middleware/rate_limit.py
- [ ] T2: Wire middleware into the request pipeline — files: app.py [deps: T1]
- [x] T0: Add Redis client for counters — files: lib/redis_client.py
```

Order tasks so each one is independently completable and verifiable — a
task that can't be checked off on its own is really two tasks.

## Step 4 — Execute, checking off as you go

Mark a task `[x]` the moment it's *verified* done, not when it's written —
re-read the file, re-run the test, per the verify-before-claiming habit.
Never re-plan from zero mid-implementation; amend `plan.md` in place if
reality diverges from the plan (add/split/reorder tasks), and keep the file
as the single source of truth for what's left.

## Step 5 — Resume, don't restart

At the start of a new session (or right after a compaction), check for
`docs/plans/*/plan.md` with unchecked tasks before starting anything new.
Resume from the first unchecked task. If the plan itself looks stale
(the codebase moved on since it was written), amend it explicitly and note
why — don't quietly abandon it.
