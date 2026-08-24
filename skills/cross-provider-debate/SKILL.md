---
name: cross-provider-debate
description: |
  The agent-driven Cross-Provider Debate (CPD) discipline — a portable CPVD
  primitive. Invokes a structured multi-critic debate cycle over a
  load-bearing decision, enforces a mandatory per-critic resume rebuttal, and
  refuses to emit a verdict until every debate is complete.

  Depends on: the critic-dispatch and critic-resume primitives, the
  verdict-builder and its incomplete-debate guard, the panel-shrinkage check,
  the calibration-append helper, and a staleness-aware coverage check/record
  pair. See the engagement CLI manifest for exactly where each of these
  lives in your engagement tooling.
---

# cross-provider-debate

The CPD discipline. A single cross-provider-debate run covers ONE load-bearing
decision. The flow is: frame-check → pre-debate budget commit → always-panel
round 1 → parallel probe → classify → mandatory per-critic resume rebuttal →
regrade → calibration append → structured verdict.

**The decision matrix refuses to render while any debate is incomplete.**
The verdict-builder raises its incomplete-debate guard when called before
every round-1 `session_id` has a paired round-2; never suppress or catch that
error to force a verdict.

**The operator arbitrates.** The engine synthesises, weighs, and proposes;
the human decides and signs. A CPD output is a structured input to human
judgment, not a replacement for it.

---

## Authoring conventions (spec + brief hygiene)

- **Revision annotations go to the debate record, never the spec body.**
  "round-N finding closed by …" breadcrumbs belong in the classify record
  (the classify-record command), the rebuttals, and the debate's reviews
  directory — the spec carries the CURRENT truth only. Annotating the spec
  grows it superlinearly across rounds and re-bills every critic for the
  history they already have.
- **Mind the brief budget.** The debate-dispatch command and the plan-debate
  flow warn above the engagement config's brief-warn threshold and refuse
  above its brief-max threshold BEFORE any dispatch (a force-brief override
  exists for a genuine exception). An oversized decision wants splitting,
  not forcing.
- **Plan-debate re-runs are delta rounds by default**: the critic's session
  is resumed with just the spec diff. Use a fresh-session override only when
  the session's context is genuinely poisoned.

---

## Anti-bias guardrails

Before dispatching any critic, explicitly confirm:
- The critic brief does NOT include the author's rationale or preferred
  conclusion — only the decision text and neutral predicates.
- Findings from round 1 are classified before the rebuttal is authored; do not
  edit the author position in response to a critic finding without re-running
  the relevant classify step.
- A "pass" verdict from round 2 does not imply the decision is correct — it
  means the critic found no fatal flaw. Surface "concerns" alongside pass
  verdicts.
- Treat `dispatch_failure` (network/timeout) as an inconclusive round, not a
  pass — retry once before escalating to the operator.

---

## Step 0 — frame-check + evidence packet

Before spending tokens:

1. State the decision in one sentence. Reject scope-creep: if the framing
   covers more than one load-bearing decision, split.
2. Identify the author family (the model family that proposed the decision).
3. Assemble the **evidence packet**: the decision text, relevant constraints,
   any prior CPD records for this decision, and the list of predicates the
   critics should evaluate. The evidence packet is read-only for critics.
4. **Verify any "already debated" claim with a staleness check — never by
   memory.** Run the coverage-check command against every file the decision
   touches:

   ```
   coverage-check --file <each file the decision touches>
   ```

   - **`REUSABLE`** (a prior debate covers these files AND every covered file
     is byte-identical since that debate) → present the prior verdict to the
     operator; with their consent, skip the rest of this skill and note
     "CPD already invoked — coverage verified unchanged."
   - **`STALE`** (any covered file changed, appeared, or vanished — however
     subtly) → the prior debate is NOT coverage. Re-debate is mandatory.
     Resume each critic's listed session (the critic-resume primitive, using
     the resume-session ids from the check output, under a NEW debate_id) so
     the critics keep their prior context instead of starting cold; frame the
     rebuttal-style brief around what changed.
   - **no rows** → no prior debate covers these files; proceed with a fresh
     debate.

   The panel-shrinkage check remains the ref-level gap check; the
   coverage-check command is the content-level one. A coverage claim backed
   by neither is a discipline violation.
5. Confirm the configured critic panel is non-empty. If empty, raise and
   halt — there is no valid critic configuration.

---

## Step 1 — pre-debate budget

Before any dispatch:

1. Count the critics in the configured critic panel.
2. Estimate token cost: 2 rounds × N critics (round 1 + round 2 resume
   rebuttal per critic). Note this estimate in the debate record.
3. If the estimate exceeds a soft cap the caller has set, surface it to the
   operator and wait for explicit approval before continuing. Never silently
   skip critics to stay under budget — budget decisions are operator decisions.
4. Record the **pre-debate budget** estimate in the debate record.

---

## Step 2 — ALWAYS-panel round 1

**Author the round-1 critic brief** (the thinking: evidence packet + predicates
+ the critic response contract below, in neutral framing), write it to a file,
then dispatch the whole panel with ONE call to the debate-dispatch command —
no hand-rolled driver:

```
debate-dispatch --debate <debate_id> --decision "<what's under review>" \
    --brief-file <brief.md> [--security-brief-file <sec-brief.md>] [--json]
```

The debate-dispatch command dispatches round-1 to EVERY critic in the
configured panel (bounded-parallel, each via the resilient critic-dispatch
primitive — a transient `dispatch_failure` auto-retries under the same
`(decision_id, critic_model)` key instead of poisoning the debate), records
each result, and persists the full critic text to the debate record's
round-1 result file. Pass a security-brief file to add a T2 `<debate>-SEC`
critic (a non-author-family model). This is the "always" panel — it always
runs in full; the cross-family invariant is enforced per critic.

Read the round-1 result file (or the command's structured-output stdout) to
classify findings in Step 3. Each entry carries `decision_id`, `critic_model`,
`session_id`, `verdict`, `finding_count`, and `critic_text`. The session ids
are what Step 5 resumes.

> Library form (only if you need custom orchestration the debate-dispatch
> command doesn't cover): the engagement library's panel-runner, or the
> resilient critic-dispatch primitive per critic. Prefer the command — it is
> the machine-friendly path and removes the boilerplate that used to be
> re-scripted every debate.

### Critic response contract (load-bearing — embed in every `critic_brief`)

A critic that returns vague "second-opinion" prose is noise. Every `critic_brief`
MUST require the critic to report each finding in this exact shape, so findings
are falsifiable and the engine can parse them (`severity:` and the final
`verdict:` line are what the critic-dispatch primitive extracts):

```
Severity: low | medium | high | critical
Mechanism: WHY it breaks — the specific causal chain, not a label.
Failure mode: what the system actually does when it breaks.
Detection signal: how this would be observed in testing / logs / a probe.
Falsifier: what evidence would change your mind (if none, say so — that flags rhetoric).
Recommendation: the concrete change, or "accept residual risk because …".
```

End the response with a single `verdict: pass | fail | concerns` line.

A severity without a **mechanism** and a **falsifier** is rhetoric — discount it
at classify time (Step 4). The contract is what lets `pattern_matched` and
`real_overweighted` be told apart from `confirmed`.

---

## Step 3 — parallel probe (facts override critic on facts)

After round 1 completes:

1. For each finding flagged as a factual claim, run a targeted read-only probe
   (Bash/Read/Grep against the codebase, NOT another model call) to verify the
   fact.
2. If the probe confirms the critic's factual claim: mark finding `confirmed`.
3. If the probe refutes the critic's factual claim: classify that finding
   `wrong` in Step 4 (the recorded taxonomy has no separate probe-refuted
   class — `wrong` backed by probe evidence IS the probe-refuted case); the
   probe result overrides the critic on that specific fact, and the
   contradiction goes in the rebuttal authored in Step 5.
4. Factual overrides do NOT change the round-1 verdict; they inform the
   per-critic rebuttal authored in Step 5.

---

## Step 4 — classify

For each finding from each critic, classify it into one of four categories
before authoring any rebuttal. Classification must be independent of the
author's preference.

| Class | Meaning |
|---|---|
| `confirmed` | Finding is accurate and materially affects the decision. |
| `real_overweighted` | Finding is accurate but its impact is overstated. |
| `pattern_matched` | Critic applied a heuristic that does not fit this context. |
| `wrong` | Finding is factually incorrect (use probe evidence from Step 3). |

Classify every finding, then RECORD the classification mechanically — JSON in,
no prose-only record:

```
classify-record --debate <debate_id> --round 1 --json <classifications.json>
```

The JSON is a list of `{finding, severity, classification, note?}` in finding
order (the 0-based index is the join key). The supersede key is
`(debate, round)` — re-running the same round replaces the earlier record.
The confirmed entries flow into the calibration log automatically at verdict
time; the trajectory reader (below) needs this record to show classification
counts.

**Convergence signal.** If every finding from every critic is classified
`confirmed`, the decision has no defence — escalate to operator immediately
without proceeding to rebuttal.

### The classification IS the escalation router

After classifying (and after round 2, when rebuttals resolve), decide
keep-going vs escalate FROM the classifications — never from the round count
(a counter can't tell a nitpick from a blocker; never escalate solely because
N rounds elapsed):

- `confirmed` with an objectively-correct fix → **fix and continue** (most
  findings; no human preference is involved).
- `real_overweighted` / `pattern_matched` / `wrong` that SURVIVES the round-2
  rebuttal → **escalate** — agent and critic disagree after evidence; the
  operator arbitrates.
- A finding that encodes an operator-owned trade-off (scope, contract change,
  cost, product intent) → **escalate regardless of category**.
- The debate-trajectory command, run against a debate id or series, saying
  `plateau` → **escalate the cost/ROI call** ("is another round worth it?" is
  a budget decision, not a correctness one). `spike` → keep going;
  `converging` → accept or run one confirming round. The trajectory is
  ADVISORY — it informs this router, it never gates anything.
- **Failed-probe downgrade:** dispatches are health-probed and the outcomes
  land on the events (`cpd_probes` / the debate event's `probes`). If the
  gating critic has a FAILED probe on record, DOWNGRADE "proceed
  autonomously" in any escalation you surface — you cannot simultaneously
  distrust the critic's verdict and lean on its sign-offs. The critic's
  non-convergence is also never the exit by itself: for plan debates the
  mechanical exit is the plan-debate-conclude command (classification-based,
  refuses on any confirmed blocker/major); for standalone debates it is the
  debate-conclude command.

---

## Step 5 — mandatory per-critic resume rebuttal

This step is **mandatory**. The resume rebuttal is NOT optional and has NO
skip conditions. **Every** dispatched panel critic receives a round-2 resume
rebuttal — including critics whose round-1 findings are all `confirmed`. A
critic with all-confirmed findings still gets a confirm/final-verdict round so
that the completeness check can pair every round-1 session with a round-2,
satisfying the structural completeness requirement.

For each critic in the configured panel that produced a round-1 session_id:

1. Author a rebuttal **separately** for each critic (per-critic authoring —
   do not merge critics into a single rebuttal prompt).
2. The rebuttal addresses each classified finding: concedes `confirmed` findings,
   pushes back on `real_overweighted` and `pattern_matched` with evidence,
   disputes `wrong` with probe results. If all findings are `confirmed`, the
   rebuttal text is a brief confirmation summary (the round still runs).
3. **Author one rebuttal per critic** into a directory, named `<decision_id>.md`
   (e.g. `<debate>-R0.md`, `<debate>-R1.md`, `<debate>-SEC.md`), then dispatch
   the whole round-2 with ONE call to the debate-resume command — no
   hand-rolled serial loop:

```
debate-resume --debate <debate_id> --pushback-dir <rebuttals/> [--standard] [--json]
```

The debate-resume command resumes each round-1 session **bounded-parallel**
(per-session store isolation ended the shared-store serialization an older
gotcha guarded against), each via the resilient critic-resume primitive (a
transient lock/flake auto-retries). A round-1 with no matching pushback file
uses the standard re-verify pushback when that mode is set, else is skipped
and reported. Results persist to the debate record's round-2 result file.

A critic whose `session_id` is missing (a genuinely failed round-1) cannot be
resumed. Do NOT hand-recover it: run the debate-repair command with its
diagnose flag to see which round-1s must be re-dispatched, then the
debate-repair command (without the flag) to resume every orphaned round-2
serially and render the verdict. Inspect state any time with the
debate-inspect command. These verbs are the mechanical, unattended-safe
path — reach for them before any manual re-keying or ad-hoc inspection.

---

## Step 6 — regrade with budget (deferred-with-tripwire)

After all round-2 rebuttals complete:

1. For each critic, note whether its final verdict (round-2) changed from
   round-1.
2. **Regrade** the decision: re-evaluate against the now-complete debate record.
   Consider whether the author position needs updating based on `confirmed`
   findings.
3. Budget check: compute total tokens consumed vs. the pre-debate budget from
   Step 1. If over budget by >50%, surface as a warning — not a block.
4. **Tripwire:** if any critic's round-2 verdict is `fail` AND the finding was
   classified `confirmed`, that finding MUST be addressed before the decision is
   finalised — do not mark the decision resolved while a confirmed fatal flaw
   stands. Surface to operator immediately.

---

## Step 7 — coverage record + calibration + structured verdict

### 7·0 — record what the debate covered

Before the calibration append, snapshot the debate's coverage so future
sessions can verify reuse instead of assuming it:

```
coverage-record --debate <debate_id> \
    --decision "<one-line decision>" \
    --file <each file the decision touches>
```

This hashes the covered files NOW and emits a `cpd_covers` event. A debate
with no coverage record cannot be safely reused later — Step 0's check will
simply not find it and a fresh debate will run (safe, but wasteful). Record
coverage for every completed debate.

### 7a — append calibration (optional enrichment)

The debate-conclude command (7b) auto-appends the calibration SKELETON — the
essential record exists without this step, and the append is dedup-keyed so
running both never duplicates. Use 7a only when the debate warrants a richer
entry (verdict flips, notable regrade notes); otherwise skip straight to 7b.

When you do enrich, record the entry:

`engagement_id` is the **engagement-root directory name** (`engagement_root.name`)
— the same value the PR-gate command's auto-skeleton and the debate-stats
command use. Any other derivation breaks the dedup key and produces a
duplicate skeleton next to your entry.

```
calibration_append({
    "engagement_id": engagement_id,   # required — raises an engagement-config error without it
    "debate_id": debate_id,
    "decision_id": decision_id,
    "decision": decision,
    "author_family": author_family,
    "critics": [<model> for each critic],
    "round1_verdicts": {<critic>: <verdict>},
    "round2_verdicts": {<critic>: <verdict>},
    "final_verdict": <see 7b>,
    "confirmed_findings": [<list>],
    "regrade_notes": "<notes>",
})
```

### 7b — structured verdict + harvest (the observable conclusion)

Conclude the debate with the debate-conclude command — this is the
standalone-CPD completion moment, and it is unconditional (the skill and the
engine ship in the same checkout; there is no version-skew state that needs a
fallback path):

```
debate-conclude --debate <debate_id> [--predicate <p> ...]
```

The command renders the structured verdict via the verdict-builder,
auto-appends the calibration skeleton as a backstop (a dedup no-op when 7a
already wrote the richer entry), and prints the **harvest moment** (a
mandatory knowledge-writeback checkpoint) — a prefilled knowledge-add draft
built from the debate record. Run, edit, or ignore the draft; nothing is
auto-written to the knowledge base.

The decision matrix **refuses to render** while any debate is incomplete —
an unpaired round-1 exits with an error (the incomplete-debate guard under
the hood). Never work around that hold. If it fires, the resume rebuttal step
was skipped for one or more critics; go back to Step 5.

The **structured verdict** shape:

```
debate:     <str>
decision:   pass | fail | escalate
predicates: <comma-separated list>   (line omitted when no --predicate was passed)
complete:   true
```

Present the structured verdict to the operator. The **operator arbitrates** —
do not auto-advance or auto-sign a gate on a CPD verdict alone. (The
debate-conclude command reports; the gate that acts on the verdict is the
PR-gate command.)

---

## Summary of invariants

- The configured critic panel defines the panel; never shrink it mid-debate.
- Every round-1 `session` must have a paired round-2 resume; the completeness
  check enforces this.
- The rebuttal is authored per-critic; merged rebuttals dilute the cross-family
  signal.
- The verdict-builder refusing to render on an incomplete debate is a
  feature, not an error to suppress.
- **A stale debate is never coverage.** Reuse of a prior debate requires the
  coverage-check command showing every covered file byte-identical; any
  drift — however subtle — mandates a re-debate (resuming the prior critic
  sessions). Record coverage (the coverage-record command) for every
  completed debate.
- Cost NEVER blocks a CPD run; budget figures are informational.
