---
name: spec-plan-pr-pipeline
description: |
  Drive a unit of work through Marshal's durable three-phase plan: spec
  ("what") → implementation plan ("how" + per-task file sets) → execution
  through the `marshal pr` gate. The artifacts live at
  `.marshal/plans/<slug>/{spec,plan}.md` as legible markdown, so the plan
  survives every session boundary (context limit, /clear, reboot, handoff) —
  a fresh session resumes from plan.md, not from zero.

  Why this exists: the in-conversation plan is ephemeral and per-machine. The
  framework's create-plan/execute-plan shape is adapted here BAKED-IN (never a
  runtime dependency on the framework's CLI). The pipeline is AUTONOMOUS
  end-to-end: the agent classifies the work, drives every stage, and never
  asks permission between phases — the operator is pulled in only by the
  mechanical escalation gates (a non-pass spec debate, a load-bearing
  decision, genuine ambiguity).
---

# spec-plan-pr-pipeline

One run drives ONE plan, end-to-end, autonomously. The verbs persist state +
events and enforce the stage gates; the thinking is yours; the operator is an
escalation target, not a scheduler.

**Mode (operator-owned config):** `.marshal/config.yaml` → `plans.autonomy`.
`autonomous` (default) = the flow below. `checkpoints` = the same flow plus
exactly two operator sign-offs the verbs mechanically require: SPEC (after the
debate — surface the spec + debate outcome, wait for `marshal plan approve
--stage spec`) and PLAN (before the first task-done — wait for `--stage plan`).
The approve verb is the operator's, never yours. Everything else stays
autonomous in both modes, and a single plan can override the engagement
default via `marshal plan new --mode …` (risky plan → checkpoints; routine
plan in a checkpoints engagement → autonomous). The PR gate never goes
autonomous in any mode — merge is always the operator's.

## When to use

- Any feature or change big enough to outlive one session, touching 3+
  files, or carrying acceptance criteria. Classify the incoming ask YOURSELF —
  a ticket that needs a plan gets one without anyone saying the word "plan".
- NOT for one-line fixes (just ship through `marshal pr`), and NOT a
  replacement for the harness's in-session plan mode — Claude Code owns the
  live todo list; Marshal owns the durable snapshot.

## Phase 0 — start

```
marshal plan new --slug <slug> --title "<one line>"
```

Grounding rules apply as always (read `.marshal/context/brief.md` first; an
ungrounded engagement refuses everything).

## Phase 1 — spec ("what")

Write `.marshal/plans/<slug>/spec.md`: problem, in-scope, acceptance criteria,
out-of-scope. Remove the not-yet-written marker. Keep it short and falsifiable —
acceptance criteria a machine or a reviewer can check.

Then record the transition (the verb refuses a skeleton):

```
marshal plan spec --slug <slug>
```

## Phase 1b — debate the spec (rule 7 as a gate)

```
marshal plan debate --slug <slug>
```

A cross-family critic stress-tests the spec. `pass` → continue immediately, no
operator involvement. Non-pass → classify the findings (confirmed /
real-overweighted / pattern-matched / wrong, probing the code where factual),
then EITHER revise spec.md and re-run, OR rebut via the cross-provider-debate resume
discipline. Only an unresolved non-pass goes to the operator — that is the
checkpoint, and it is the exception.

**Interlocks (v0.13.0) — the loop is bounded and never blocks on a picky
critic:**

- **Attempt cap** (`plans.debate_max_attempts`, default 4): at the cap the
  verb refuses another round and routes to the conclude path below. The bar
  for one more round vs concluding is the FINDINGS, never the critic's
  verdict token: a round is still valuable iff it produced at least one NEW
  finding you CONFIRMED against the code/spec at blocker/major. Zero such
  findings → the critic is pattern-matching → conclude.
- **Critic health**: every dispatch probes the critic first (recorded on the
  event). A failed probe on a single-critic plan debate refuses outright —
  run `marshal doctor`.
- **Conclude by classification** — the picky-critic exit, no `pass` token
  needed:

  ```
  marshal cpd-classify --debate plan-<slug> --round 1 --json <entries.json>   # put your Step-4 taxonomy ON THE RECORD
  marshal plan debate-conclude --slug <slug>
  ```

  Concludes mechanically iff attempts >= 2, EVERY finding of the latest
  attempt is classified on the record, and none is a confirmed
  blocker/major. The classification backfill is the intended dance — debate
  rounds don't require recording classifications; the conclude path does.
  A confirmed blocker/major always refuses: resolve it or escalate — conclude
  never overrides a confirmed load-bearing finding. `plan draft` re-validates
  the basis from the events, so only an honest conclude unblocks phase 2.

**Escalation ranking under a failed probe:** if the gating critic has a
failed health probe on record, DOWNGRADE "proceed autonomously" in any
escalation you surface to the operator — a degraded critic's sign-offs are
exactly the evidence you cannot lean on. (Defense-in-depth: the conclude path
above usually removes the need for the escalation menu entirely.)

## Phase 2 — implementation plan (gated on the debate) ("how" + which files)

Write `.marshal/plans/<slug>/plan.md` as an ordered task checklist. One line
per task; **every task names its file set** — this is the feature→files record
(WS-C), legible to teammates who don't run Marshal:

```
- [ ] T1: collapse the address form — files: src/checkout/address.py, src/checkout/forms.py
- [ ] T2: wire the payment intent — files: src/checkout/payment.py [deps: T1]
```

**Task ordering is DECLARED with a trailing `[deps: T1,T3]` tag — never
prose.** The wave engine honors `[deps:]` edges in addition to write-set
conflicts; a "Dependencies:" prose line is REFUSED at `plan draft` (the
planner would not honor it — this exact trap cost a production run).

Note cross-area impact as prose where it is cheap (an `affects: ios, backend`
line under a task) — judgment + the review gate own cross-area safety; there
is deliberately no computed impact graph. Remove the not-yet-drafted marker.

Then record it — this is also where **execution mode** is chosen
(dual-mode-execution): `--execution dispatch|inline` picks explicitly;
absent the flag, `plans.execution_mode` (config) then `dispatch` decide.
The mode is recorded on this draft's event and travels with it until a
NEW draft changes it:

```
marshal plan draft --slug <slug> [--execution dispatch|inline]
```

The verb REFUSES without a passed spec debate (genuinely trivial plans:
`--trivial "<reason>"` — >= 20 chars, recorded in the event, auditable). It
parses the checklist, refuses duplicate/absent task ids, and loudly counts
tasks with no `files:` list — fill the file set in wherever it is known.

**The chooser line.** The same parallelism-lint output `plan draft` already
prints carries a recommendation: `wave_count == task_count` (fully
serial — every task conflicts with or depends on its neighbor) prints
*"no parallelism to lose — inline keeps the orchestrator's context, skips
the executor cold-start"*; `wave_count < task_count` prints the dispatch
recommendation with the parallel width (the largest wave). It is a
recommendation, never coercion — surface it to the operator when the flag
wasn't given explicitly, and record whichever mode is actually chosen (a
re-draft with the other `--execution` value if the default doesn't fit).
Full rationale + the measured cold-start/context-transfer numbers behind
the recommendation: [operations.md § Dual-mode plan
execution](../../docs/operations.md#dual-mode-plan-execution-dispatch--inline).

## Phase 3 — execute

Phase 3 forks by the plan's **recorded** execution mode (whichever
`plan draft` call above actually recorded) — same walls, same gate,
different hands. Neither flow pauses for operator check-ins between
tasks; continuous execution in both.

### Dispatch flow (recorded mode: `dispatch` — today's path, unchanged)

Task by task, in order (respect dependencies):

1. Do the work. Verify before claiming (discipline rule 3).
2. Ship each shippable unit through the normal gate — `marshal review` →
   `marshal pr`. **The plan never bypasses the PR gate** (rule 8).
3. Record durable progress the moment a task is truly done:

```
marshal plan task-done --slug <slug> --task T<N>
```

(Or run the whole open task set through the wave engine directly:
`marshal plan run --slug <slug>` — see [cli-reference.md § plan
run](../../docs/cli-reference.md#plan-run).)

### Inline flow (recorded mode: `inline`)

Per task, in order (respect dependencies) — `task-done` plays **no part**
in this flow; `task-fold` records completion itself:

```
marshal plan task-start --slug <slug> --task T<N>
```

Eligibility walls (each refusal names its remedy): the plan must be
drafted with **inline** recorded (a dispatch/legacy plan refuses — re-draft
with `--execution inline`); the task's deps must be folded; no leftover
artifacts from a prior attempt; no OTHER task's inline worktree may be
live (strict serial — one task in flight at a time). On success it prints
a worktree path and a materialized brief path — the SAME context a
dispatched executor's prompt would carry, with nothing to spin up.

Do the work in the **printed worktree** — never the main checkout — under
the same work-order discipline a dispatched executor follows: bite-sized,
verify-as-you-go, narrowest test selection. Wrap every test/lint invocation
in the bounded-output wrapper — `marshal verify-capture -- <your command>` —
exactly as the verification doctrine tells a dispatched executor: the
excerpt stays small in YOUR context too, and the complete redacted output
lands in a log the framing line names (grep the log instead of re-running
bare). **Commit the edits on the task
branch** (any number of commits) as you go — this is the one place Marshal
expects the agent, not Marshal itself, to build the commits. Then:

```
marshal plan task-fold --slug <slug> --task T<N>
```

`task-fold` refuses an uncommitted worktree (the same dirty-tree class
dispatch enforces) — commit before folding. On success it runs the exact
fold pipeline a dispatched wave uses (task-scoped verify, the
undeclared-write fence, the marker commit, merge, completion recording +
the plan.md checkbox) and deletes the worktree. On a verify failure or
fence refusal it folds nothing and retains the worktree — fix in place and
re-run `task-fold` (idempotent). Full verb detail: [cli-reference.md §
plan task-start /
task-fold](../../docs/cli-reference.md#plan-task-start--plan-task-fold).

**Refusal runbook — `plan run` on an inline plan:** running the dispatch
verb against an inline-recorded plan refuses, naming the next eligible
task and the `task-start`/`task-fold` pair above as the remedy.
`--dispatch` is the explicit, recorded override if you genuinely want a
one-off dispatched run instead — it still refuses under the run lock while
an inline task's worktree is live and unfolded.

**Neither flow relaxes a wall:** worktree-only edits, verify before fold,
the fence on every fold, the gate before `marshal pr`, and an
operator-only merge — identical in both flows (rule 8; [operations.md §
The walls that never
relax](../../docs/operations.md#the-walls-that-never-relax)).

**Failure recovery playbook — a failed task's retained worktree is never
auto-deleted.** Three verbs recover it; pick by what happened and how much
of the retained work is worth keeping ([operations.md § Recovery decision
table](../../docs/operations.md#recovery-decision-table) has the full
comparison):

- **`plan run --retry <id>`** — discard the retained worktree/branch and
  re-run the task fresh. Use when the work isn't worth keeping, or the
  task definition changed and you want the revised contract to run clean.
- **`plan run --salvage <id>`** — adopt committed, non-content-failure
  residue with ZERO re-dispatch (a `task-verify`-stage failure, worktree
  untouched since). Narrow eligibility, cheapest recovery when it fits.
- **`plan task-start --repair` → fix in place → `plan task-fold --repair`**
  (spec AMENDMENT 1) — the common case the other two miss: a near-complete
  attempt (dispatched OR inline) needs a small, targeted content fix.
  `task-start --repair` validates the identity wall (worktree registered on
  the task's own branch) and the contract-version wall (the failed
  attempt's recorded contract must equal the CURRENT task definition — an
  amendment since the failure refuses, naming `--retry` instead), records a
  **repair reservation**, and prints the worktree path + failure evidence
  (a verify-log tail when persisted, else the recorded failure reason).
  Fix the tree, **commit** it (same discipline as the inline flow above),
  then `task-fold --repair` — the UNCHANGED fold pipeline, gated on the
  active reservation, tagging the completion with a repair transport
  marker. Without `--repair`, folding a failed DISPATCHED attempt's
  retained worktree refuses outright, naming all three options above — this
  does NOT gate an INLINE task-start's own failed fold, which keeps its
  ordinary ungated retry-in-place (fix + re-run `task-fold`, no flag). While
  a reservation is active, `--retry`/`--continue`/`--salvage` and a bare
  `plan run` all refuse the reserved task — fold it, or discard it
  explicitly with `plan run --retry <id> --override-repair`.

**Session-boundary resume:** on a fresh session with an active plan (visible in
`marshal status` / `marshal go` orientation), read `.marshal/plans/<slug>/`
top to bottom and resume from the first unchecked task — in the inline flow
that means the next eligible task's `task-start`, not `task-done`. Never
re-plan from zero while an active plan exists — amend the plan file
instead, and re-run `marshal plan draft` if the task list changed shape
(a re-draft can also change the recorded execution mode).

## Completion

When every task is checked:

```
marshal plan complete --slug <slug>
```

The plan moves to `.marshal/plans/_archive/<slug>/` (a stale active plan never
misleads the next session). Then run the rule-13 harvest: did this plan teach a
gotcha or a pattern? `marshal knowledge add` it; promote it to the repo's
committed KB (`marshal knowledge promote`) when it proves out.

Plans are operator-local by default. To make them legible to teammates,
`marshal plan share` migrates the store (active + archive) to committed
`docs/plans-staging/`; `marshal context share` does the same for the dossier.
Committed files are review snapshots — plan state stays in the local event
log, and foreign snapshots are read-only ([operations.md § Sharing plans &
dossier](../../docs/operations.md#sharing-plans--dossier-between-operators-opt-in)).

## Failure modes this skill exists to prevent

- The plan living only in the conversation and evaporating at the context
  limit.
- The executor rediscovering the file set every session (the plan's `files:`
  lists are the map).
- "Done" claimed with open tasks — `plan complete` refuses; the checklist is
  the ground truth.
- A parallel plan store nobody else can read — plans are markdown in the
  engagement's own substrate (operator-local by default: `.marshal/` is
  gitignored; `marshal plan share` opts the store into committed
  `docs/plans-staging/` — shared files are review snapshots, state stays
  operator-local).
