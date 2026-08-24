---
name: ready-to-pr-review
description: |
  The agent-driven ready-to-pr orchestration gate for Marshal. Runs marshal review
  to collect the gates+intent+tier bundle, conducts a cross-family panel via
  dispatch_cpd (every critic in cfg.critic_panel) against the selected rubric plus
  a security pass at the classified tier, enforces mandatory per-critic
  critic-of-synthesis via dispatch_cpd_resume, builds the verdict via
  build_cpd_verdict (which refuses on an incomplete debate), frames it with the
  anti-false-confidence disclaimer, then either runs marshal pr (draft, merge held)
  or surfaces a HOLD to the operator via self-DM.

  Depends on:
    dispatch_cpd / dispatch_cpd_resume  (marshal_core/dispatch.py)
    build_cpd_verdict / IncompleteDebateError  (marshal_core/cpd_audit.py)
    security_tier / select_rubric / security_review_prompt  (marshal_core/review.py)
    cfg.critic_panel  (MarshalConfig)
    marshal review / marshal pr  (CLI)

  Grounding: the engagement MUST be grounded (repo-dossier-onboard run and
  context_present = True) before this skill produces a meaningful verdict.
  An ungrounded engagement produces low intent-confidence, which downgrades any
  confident READY verdict — run repo-dossier-onboard first.
---

# ready-to-pr-review

The agent-driven gate between "code is written" and "PR is open." It runs the
cross-family CPD discipline over every critic in `cfg.critic_panel`, enforces the
mandatory per-critic critic-of-synthesis rebuttal, and only opens a PR
(merge held) when the completed panel returns a unanimous `pass` verdict.

**Framing invariant.** The final output MUST carry this disclaimer verbatim:

> Automated gate passed; human review still required — NOT a safety guarantee.

**Cross-family disagreement is surfaced, not collapsed.** When critics disagree,
the skill presents every critic's verdict and findings side-by-side. The operator
arbitrates; the skill never silently merges divergent findings into a single
synthesised position.

**Anti-false-confidence.** Low intent-confidence (from the `marshal review` bundle)
downgrades a confident READY verdict: a `pass` panel verdict combined with
`confidence: low` surfaces as READY-WITH-CAVEAT, not READY. The operator still
decides; the caveat ensures the reviewer reads it.

---

## Prerequisites

1. The engagement MUST be grounded. Run `repo-dossier-onboard` first:
   - `.marshal/context/brief.md` and `.marshal/context/repo-map.md` must exist
     with non-placeholder content.
   - `context_present(engagement_root)` returns `True`.
   - If ungrounded: surface "run `marshal onboard` then repo-dossier-onboard skill"
     and STOP. Do not proceed — the intent bundle will carry `confidence: low`
     and the rubric selection will fall back to `Unknown / Mixed`.

2. `marshal doctor` must be green. OpenCode is a hard precondition for critic
   dispatch. Red doctor → STOP, surface the remediation.

3. `cfg.critic_panel` must be non-empty. If empty → raise and halt; there is no
   valid critic configuration.

---

## Step 0 — Run the bar ONCE via `marshal review run`, then collect the bundle

**Step 0a — Run `marshal review run` (the gate's "verify" leg — the ONLY bar
execution).** This leg MUST actually execute — it is never assumed. It runs
the engagement's configured `verify.commands` (tests + lint), the secrets
scan, and records the sha-keyed proof at the current HEAD in one pass. Do
NOT run the test suite separately first: the two runs have identical
coverage, and on a real suite that doubles the gate's wall-clock for nothing
(measured ~400s × 2 on this engagement — the exact waste this step exists to
prevent).

The bar runs against the **git repository root** — NOT necessarily the
engagement root. In the root-wraps-repo layout (the engagement root holds
`.marshal/` while the repo is a subdirectory) verify must run against the
repo or it tests the wrong tree; `verify.commands` in `.marshal/config.yaml`
own that resolution (or read `repo_root` from the Step 0b bundle). If the
engagement has no `verify.commands`, configure them first — by stack:
`pyproject.toml` → `uv run pytest -q`; `package.json` → `npm test`;
`Cargo.toml` → `cargo test`.

If the bar **fails (non-zero exit)**: emit `NOT READY: verify failed`,
surface the failing output (the recorded proof carries it), and
SHORT-CIRCUIT — no panel, no PR, no model dispatch. The operator must make
verify green before re-running. Only proceed to Step 0b on a green bar.
After any fix commit, re-run `marshal review run` — the proof is keyed to
the exact sha, so a stale proof never covers new code.

**Step 0b — Collect the gate bundle.** Run `marshal review` to collect the
gates+intent+tier bundle:

```bash
marshal review [target]
```

The command emits a JSON object with:

| Key | Description |
|---|---|
| `intent` | Extracted intent string (from `.marshal/context/brief.md` via repo-dossier-onboard) |
| `archetype` | Engagement archetype (inferred during onboarding) |
| `confidence` | `"high"` or `"low"` — grounding quality indicator |
| `tier` | Security tier: `"T1"` (diff-scoped) or `"T2"` (full-repo) |
| `reason` | Human-readable tier reason |
| `files` | Changed file paths in the diff |
| `loc` | Lines of code added |
| `secrets` | Redacted secret indicators found in the diff |
| `rubric_version` | Version of the loaded review rubric |
| `repo_root` | Git repo root the diff was taken from — confirms where Step 0a's bar ran |

**NOT READY short-circuit (check before any dispatch):**

- If `secrets` is non-empty → surface each redacted indicator to the operator,
  emit `NOT READY: secrets found in diff`, and STOP. No PR, no panel. The
  operator must remediate before re-running.
- If `marshal review` exits non-zero (verify failure, git error) → surface the
  error, emit `NOT READY: gate command failed`, and STOP.

Record the bundle for use in subsequent steps.

---

## Step 1 — Select rubric + security scope

From the bundle:

1. The rubric is already selected by `marshal review` (via `select_rubric`); its
   version is in `rubric_version`. Load the rubric text via `select_rubric` from
   `marshal_core.review` using the `archetype` field from the bundle.

2. Determine the security pass scope:
   - `tier = "T1"` → diff-scoped security review. The security pass covers only
     the changed files and diff hunks.
   - `tier = "T2"` → full-repo security review. The security pass covers the
     entire repository, not just the diff. Surface the T2 escalation reason
     (`bundle["reason"]`) to the operator before running T2 critics.

3. Load the security prompt via `security_review_prompt()` from `marshal_core.review`.

---

## Step 2 — Confirm `cfg.critic_panel` and pre-dispatch budget

1. Read `cfg.critic_panel` from the loaded `MarshalConfig`.
2. Confirm it is non-empty. If empty → raise `MarshalError` and halt.
3. Estimate token cost: 2 rounds × N critics (round 1 + round 2 --resume per
   critic) + security pass. Surface the estimate to the operator. Cost is
   informational — never halts dispatch.
4. Confirm the `debate_id` to use (derive from `run_id` or generate a stable ID
   anchoring this review cycle).

---

## Step 3 — ALWAYS-panel: `marshal cpd-run`

**Author two briefs** (the thinking), write each to a file, then run the whole
panel + security pass with ONE command — no hand-rolled `ThreadPoolExecutor`:

```bash
marshal cpd-run --debate <debate_id> --decision "Code review: <intent>" \
    --brief-file <panel-brief.md> --security-brief-file <sec-brief.md> [--json]
```

`cpd-run` dispatches round-1 to EVERY `cfg.critic_panel` critic against the panel
brief (bounded-parallel, each via `dispatch_cpd_resilient` — a transient
`dispatch_failure` auto-retries under the same `(decision_id, critic_model)` key),
AND adds the T2 `<debate>-SEC` critic (a cross-family model) against the security
brief. It records every `cpd_result` and persists the full critic text to
`.marshal/reviews/<debate_id>/round1.json`. The security pass shares the debate
and is a round-1 exactly like every panel critic — so it gets a paired round-2 in
Step 5, never left unpaired.

The **panel brief** MUST:
- Include the full rubric text (from `select_rubric`) + the diff bundle.
- Be **neutral** — no author conclusions or rationale.
- Open with a `# HARD RULES` block forbidding Task/Agent dispatch, tool use
  read-only (≤ 8 calls).
- **Require the exact verdict token**: END with `verdict: pass` (or
  `verdict: concerns` / `verdict: fail`) on its own line. An unrecognizable
  reply is scored fail-closed (`concerns`), so the exact token avoids a false
  escalate.

The **security brief** MUST include the full `security_review_prompt()` + the
tier scope note (`T1` diff-scoped / `T2` full-repo) + the same HARD RULES.

Read `round1.json` (or `--json` stdout) to classify findings in Step 4 — each
entry carries `decision_id`, `critic_model`, `session_id`, `verdict`,
`finding_count`, `critic_text`. The session ids (every panel critic PLUS the
security pass) are what Step 5 resumes. `cpd-run` enforces the cross-family
invariant per critic and auto-retries a transient dispatch failure, so a missing
`session_id` after that is a genuine failure — recover with
`marshal cpd-repair` (never a synthetic "pass").

> Library form (custom orchestration only): `cpd_orchestrate.run_panel(...)`.
> Prefer the command.

---

## Step 4 — Classify findings

For each finding from each round-1 critic, classify before authoring any rebuttal:

| Class | Meaning |
|---|---|
| `confirmed` | Finding is accurate and material. |
| `real_overweighted` | Finding is accurate but impact is overstated. |
| `pattern_matched` | Critic applied a heuristic that does not fit this context. |
| `wrong` | Finding is factually incorrect (use read-only probe to verify). |

Run targeted read-only probes (Bash/Read/Grep against the codebase) to verify
factual claims before classifying. Probe results override critics on facts.

**Convergence signal**: if every finding from every critic is `confirmed`, the
change has no defence — escalate to the operator immediately without rebuttal.
Surface all confirmed findings and emit HOLD.

---

## Step 5 — Mandatory per-critic critic-of-synthesis via `dispatch_cpd_resume`

This step is **mandatory**. Every dispatched round-1 receives a round-2 `--resume`
rebuttal. The resume set is explicitly **every round-1 dispatched in Step 3** —
that is, every member of `cfg.critic_panel` PLUS the security pass. The security
pass is NOT exempt: it shares the debate, so leaving it as an unpaired round-1
would make `debate_complete`/`build_cpd_verdict` raise `IncompleteDebateError`.
The per-critic critic-of-synthesis is the CPD discipline — consume it, do NOT
re-implement or skip it.

**Author one rebuttal per critic** (never merge critics) into a directory, each
named `<decision_id>.md` (`<debate>-R0.md`, …, `<debate>-SEC.md`). Each rebuttal
concedes `confirmed` findings, pushes back on `real_overweighted`/`pattern_matched`
with evidence, disputes `wrong` with probe results; an all-confirmed critic still
gets a confirm/final-verdict round. Then dispatch the whole round-2 with ONE
command — no hand-rolled serial loop:

```bash
marshal cpd-resume --debate <debate_id> --pushback-dir <rebuttals/> [--json]
```

`cpd-resume` resumes every round-1 session **bounded-parallel** (per-session
store isolation — concurrency Phase 0 — ended the shared-db serialization)
via `dispatch_cpd_resume_resilient`, matching each
critic's pushback by `decision_id`, and persists to
`.marshal/reviews/<debate_id>/round2.json`. A critic without a `session_id`
(genuine dispatch failure) is skipped and reported — recover with
`marshal cpd-repair`, never a synthetic pass. Inspect state with
`marshal cpd-show --debate <debate_id>`.

---

## Step 5b — Proportionality: fix-round depth is set by the tier

A **fix-round** is one classify → fix-commit → `cpd-resume` cycle after
round 1. The gate's tier (the same light/standard/full tier that sizes the
panel — `cpd-run` prints it with its `fix-round depth:` value) also sets how
deep the gate iterates:

| Tier | Fix-round depth |
|---|---|
| `light` | 1 fix-round |
| `standard` | 2 fix-rounds |
| `full` | orchestrator judgment — see the conclude rule below (two consecutive dry rounds, or one dry round with a recorded `--conclude-reason`) |

**The conclude rule — a dry round is the mechanical stop signal.** A
fix-round is a **dry round** when its recorded `marshal cpd-classify`
`new_confirmed_major` counter is `0` — the exact mechanical counter
`count_new_confirmed_major` computes (never a re-derived approximation;
this is the one-counter-one-definition invariant: the doctrine and the
CLI's printed `new_confirmed_major` / `DRY ROUND` line must never
diverge). The tier decides how a dry round ends iteration:

- **`light` / `standard`** conclude the moment **any one** fix-round is
  dry — proportionality never spends the tier's remaining depth budget
  once the debate has stopped producing new confirmed major/blocker
  findings, even if the tier's table above still has budget left.
- **`full`** concludes on its own signal only after **two consecutive
  dry rounds** — one dry round alone is not enough evidence at full tier.
  Concluding at `full` after a single dry round is permitted only with a
  recorded `--conclude-reason` on that round's `marshal cpd-classify`
  call (a real sentence, >= 20 chars, recorded verbatim on the
  `cpd_classified` event) — an explicit, auditable orchestrator judgment
  call, never a silent shortcut. Absent both the second consecutive dry
  round and a `--conclude-reason`, `full` keeps iterating per orchestrator
  judgment.

A round that fixes findings from a PRIOR fix round (a fix-of-fix) is
itself classified with `--fix-round` — the flag that excludes
`display`/`style`/`docs`-classed findings (the `finding_class` taxonomy)
from the `new_confirmed_major` count, so cosmetic churn surviving from an
earlier fix can never masquerade as new signal. `same_as` lineage (below)
applies across fix-of-fix rounds exactly as it does across any other
round pair.

Concluding by any of these routes never changes the verdict contract:
the rendered decision stays exactly `pass` / `fail` / `escalate` (Step
6) — the dry-round / `--conclude-reason` record lives on the
`cpd_classified` event and the residual ledger below, never as a fourth
verdict token. It also never waives a confirmed blocker: the blocker
exemption below still governs, and every non-blocker residual from a
concluded debate — dry-round-concluded or not — still gets its
`gate-residual-` ledger entry, tagged with its `finding_class` when one
was recorded, so a residual reads as a member of its class, not a
one-off.

**The whole-debate residual ledger.** Residual membership is defined across
ALL rounds of the covering debate — never just the latest round: every
finding classified `confirmed` or `real_overweighted` in ANY round that has
not since been (a) **fixed** — a fix commit named in a recorded rebuttal or
classification note — or (b) **reclassified** in a later round (`wrong` /
`pattern_matched`, with probe evidence) is a residual. Finding identity is
the `cpd-classify` record's (round, index). **Lineage:** when a round's
finding restates an earlier one, record `same_as: r<round>-<index>` in its
classification note pointing at the earliest occurrence — the chain is ONE
finding; "NEW" (for full-tier termination) means a finding with no
`same_as` reference, and residual metadata renders each lineage once, under
its earliest identity.

**Blocker exemption — the cap never ships a confirmed blocker.** An
unresolved confirmed BLOCKER at any depth and any tier → `NOT READY`,
escalated to the operator. Operator arbitration may RECLASSIFY a finding
(wrong / pattern-matched / overweighted) or direct a fix — it may not waive
a finding that stands as a confirmed blocker.

**At the cap (no blocker in the residual set):** the verdict is **READY,
with residuals as metadata** — NEVER a third verdict token; the contract
every consumer (including `marshal pr`) knows stays `READY` / `NOT READY`.
(Step 6's READY-WITH-CAVEAT is the same species — a `pass` carrying
low-intent-confidence caveat metadata on the SURFACE, not a distinct
verdict token; residuals and caveats compose on one READY verdict.)
Record each residual, then name every one in the verdict surface AND the PR
body; the operator arbitrates residuals at the manual merge click:

```bash
marshal knowledge add --kind gotcha \
    --label gate-residual-<debate>-r<round>-<n> \
    --text "<summary> · severity: <sev> · <file-if-any>"
```

`<debate>` is the EXACT covering debate id (the one `cpd-covers record
--debate` records), `<round>` the fix-round, `<n>` the 1-based index within
it. **Idempotence:** grep `.marshal/knowledge/gotchas.md` for the exact
label first — an existing label is SKIPPED, never duplicated. **Lifecycle:**
a residual later fixed or disproven is deprecated in the fixing session
(`marshal knowledge deprecate --kind gotcha --label gate-residual-… --reason
"fixed in …"`). Selection for the verdict surface and PR body: exactly the
NON-DEPRECATED entries whose label starts with `gate-residual-<debate>-` —
deprecated entries and other debates' entries are never surfaced.

Residual findings are recorded as backlog, **not iterated** — the depth
table above is the brake on gate escalation; proportionality is the repair
for the unbounded-fix-round failure mode (a light change must never consume
a full-tier escalation budget).

---

## Step 6 — Verdict via `build_cpd_verdict`

Call `build_cpd_verdict` to render the structured verdict:

```python
from marshal_core.cpd_audit import build_cpd_verdict, IncompleteDebateError

verdict = build_cpd_verdict(events, debate_id, predicates=predicates)
# verdict["decision"] is one of: pass | fail | escalate
```

`build_cpd_verdict` **refuses** to render while any debate is incomplete —
`IncompleteDebateError` is raised if any round-1 session lacks a paired round-2.
Never catch that error to force a verdict. If it raises: the critic-of-synthesis
step (Step 5) was incomplete for one or more critics — go back to Step 5.

**Verdict framing (mandatory)**:

Emit the verdict with this disclaimer verbatim:

> Automated gate passed; human review still required — NOT a safety guarantee.

**Surface cross-family disagreement — do not collapse:**
If critics return different verdicts (e.g. one `pass` and one `concerns`), present
each critic's verdict and findings side-by-side. The overall decision follows
`build_cpd_verdict`'s logic (any `fail` → fail; any `concerns` → escalate;
all `pass` → pass), but the individual findings remain individually visible.
Collapsing disagreement into a single "concerns noted" sentence is forbidden.

**Intent-confidence downgrade:**
If `bundle["confidence"] == "low"` (engagement is ungrounded — repo-dossier-onboard
was not run or produced no real content), a `pass` verdict surfaces as
READY-WITH-CAVEAT, not READY. Include the caveat:

> Intent confidence is LOW — the engagement context from repo-dossier-onboard may be
> missing or stale. Human review should verify that the intent framing is correct.

---

## Step 6.5 — You are the arbiter (the self-arbitration exit)

**The orchestrator is the arbiter. You make the final call — not the critic's
verdict token.** A non-`pass` decision is NOT an automatic HOLD: the exit from
a review debate is the FINDINGS assessment, exactly as the gate-economics
doctrine established for plan debates. Extract the valuable findings, fix or
refute what is real, and CONCLUDE when a round stops adding value.

**Every round, ask: am I looping unnecessarily when I could be shipping?**
A critic that returns `concerns` while every finding it raised is already
fixed and pinned is being picky — the pickiness is the signal to conclude,
not to dispatch again. Re-dispatching a critic purely to harvest the word
`pass` is the anti-pattern this step exists to kill.

**The mechanical conclude path** (no re-dispatch to change a token):
1. Classify the latest round on the record — `marshal cpd-classify --debate
   <id> --round <N> [--fix-round] [--conclude-reason "<≥20 chars>"] --json
   <file>`. `--fix-round` excludes display/style/docs findings from the
   `new_confirmed_major` counter; a round with `new_confirmed_major == 0` is
   a DRY ROUND.
2. Go STRAIGHT to `marshal pr`. It opens the PR on a **conclude basis** when
   the latest assessment round is fully classified, dry per the tier truth
   table (light/standard: one dry round; full: two consecutive dry rounds OR
   one dry round + a `--conclude-reason`), and carries no `confirmed`
   blocking finding — recording verdict `CONCLUDED` and stamping
   `gate: CONCLUDED · <sha>` (distinct from a unanimous `gate: READY`, so a
   reviewer always sees it was arbitrated). A confirmed blocker/major in the
   latest round always refuses — conclude never overrides one.

**Evidence-first rebuttals** (when you DO rebut): a critic without repo
access cannot verify a claimed fix — include the fix diff INLINE in the
pushback (`git show <sha>`), state the fresh verify result, and ask for the
verdict on that evidence. A rebuttal that only asserts "fixed" wastes the
round (the round-2 waste class).

**When to still HOLD for the human:** a `confirmed` blocking finding you
cannot resolve, a genuine cross-family disagreement on a load-bearing call,
or an `escalate` where the confirmed findings are real and unfixed. The
arbiter concludes on pickiness; the arbiter escalates on substance.

---

## Step 7 — PR or HOLD

### On a `pass` OR a concluded basis (or READY-WITH-CAVEAT): run the bar, then `marshal pr`

**First, RUN THE MECHANICAL BAR** — the review proof, not skill adherence, is
what attests tests/lint/secrets ran:

```bash
marshal review run [target]
```

This executes the secrets scan + every `verify.commands` entry and records
the sha-keyed proof at `.marshal/review-gate/<HEAD>.json`. It refuses on a
dirty worktree (commit or stash first) and exits non-zero on a red bar — fix
and re-run before proceeding. When the engagement sets
`gate.require_review_proof` / `gate.require_coverage`, `marshal pr` will HELD
without this proof (and without a `cpd-covers record` covering the diff);
with the flags off it warns. Record coverage in Step 7·0 of the cross-provider-debate
skill BEFORE `marshal pr` so the coverage component sees it.

**Then AUTHOR the PR description — MANDATORY.** Operators read PR bodies; a
human-first write-up is the deliverable, not an option. The pinned shape:
**What changed / Why / What you'll notice (operator-visible behavior) /
Files / Evidence** (fold in root cause, sibling-PR relationships, and the
test plan where they fit). Write it to a file and pass it; `marshal pr`
preserves it **VERBATIM** and only APPENDS the gate stamp (plus the
verify-evidence line, when earned) below it — the gate must NEVER replace
your description with a stub.

```bash
marshal pr [target] --title "<PR title>" --body-file <path-to-description.md>
```

**`marshal pr` REFUSES without `--body`/`--body-file`** (v0.29.0) — the old
silent commit-message fallback now requires the explicit
`--body-from-commits` escape (mutually exclusive with the body flags,
recorded as `body_source` on the gate proof). Empty/whitespace bodies refuse
identically. Do not reach for the escape to save a round-trip: authoring the
body IS this step.

This opens a **normal Open PR** — merge held by review / branch protection (not draft
status). The body is YOUR description, with the gate stamp appended beneath
it (the anti-false-confidence disclaimer renders on the verdict surface and
the `marshal pr` console — never in the client-facing PR body).

`marshal pr` also records the sha-keyed gate proof at
`.marshal/pr-gate/<head-sha>.json` and stamps the PR body with
`— Generated with Marshal · gate: READY · <sha7>`. That stamp is how a reviewer
(or `marshal pr-audit`) tells a gated PR from an ungated one; the pre-push hook
reads the same proof. Because the proof is keyed to the exact commit, a fix
commit after this run requires re-running `marshal pr` before pushing again.

Do NOT pass any automatic-merge flag — merge is operator-gated.

### On an `escalate` or `fail` verdict: arbitrate first (Step 6.5), then conclude or HOLD

An `escalate`/`fail` decision is the START of the arbiter's assessment, not
its end. First apply Step 6.5: if every driving finding is fixed-and-pinned
or refuted-with-evidence and the latest round is a classified dry round, take
the conclude path — do NOT HOLD on pickiness. HOLD only when the substance
survives: a confirmed blocking finding you cannot resolve, or a genuine
load-bearing disagreement.

When you do HOLD, surface the reason to the operator. Do not open a PR. The
escalation surface must include:
- The overall verdict decision (`fail` / `escalate`).
- The full per-critic findings (not a collapsed summary).
- The confirmed findings that drove the escalation.
- A suggested resolution path (e.g., "address [finding] in critic [X]'s feedback
  before re-running ready-to-pr-review").

---

## Step 8 — Surface outcome to the operator's Slack channel

Regardless of the verdict, surface the outcome to the operator via the governed
posting verb — never a Slack MCP tool (an MCP user-token session is read-only
by standing rule, and MCP posting bypasses the fail-closed post governors):

```bash
marshal slack-send --channel <operator-role channel id> --text "<outcome>"
```

The operator channel comes from the engagement's `watch.channels` config
(`role: operator` — the operator's DM with the bot in bot-token mode, or the
self-DM in user-token mode). No `[watch]` config → the verb refuses; report
the outcome in-session instead and note that Slack surfacing is unconfigured.

The message must include:
- Verdict: `READY` / `READY-WITH-CAVEAT` / `HOLD (escalate)` / `NOT READY (fail)`
- PR URL (if opened) or held-reason (if not).
- One-line intent summary (from the bundle).
- Anti-false-confidence reminder: "human review still required — NOT a safety guarantee."

Do NOT post to the client channel. Operator-role channel only.

---

## Anti-patterns

- **Skipping the critic-of-synthesis.** `dispatch_cpd_resume` is mandatory for
  every panel critic. Skipping it leaves debates incomplete and `build_cpd_verdict`
  raises `IncompleteDebateError`.
- **Catching `IncompleteDebateError` to force a verdict.** Never do this. The
  error is the structural guard — honor it.
- **Collapsing cross-family disagreement.** Surface every critic's findings
  individually. A merged "concerns noted" line hides the cross-family signal.
- **Opening a PR without a completed panel.** The PR MUST follow a completed,
  complete-debate verdict. No panel → no PR.
- **Skipping the secrets short-circuit.** A diff with secrets in the bundle
  must never reach the panel. Short-circuit at Step 0.
- **Sending to the client channel.** The outcome surfaces to the operator-role
  channel only — never to the engagement client channel.
- **Posting via a Slack MCP tool.** The governed path is `marshal slack-send`;
  MCP posting bypasses the post governors and the read-only user-token rule.
- **Merging automatically.** The PR has merge held. The operator opens the
  merge when ready. The skill never merges on its own.

---

## Summary of invariants

- `marshal review` gates+intent+tier bundle is the input; secrets or verify
  failures cause NOT READY short-circuit before any model dispatch.
- `cfg.critic_panel` defines the panel; every member runs in round 1.
- Every round-1 session receives a per-critic `dispatch_cpd_resume` rebuttal
  (the critic-of-synthesis); `debate_complete` enforces pairing.
- `build_cpd_verdict` refuses on an incomplete debate — this is a feature.
- Cross-family disagreement is always surfaced to the operator; never collapsed.
- Fix-round depth follows the tier (light=1, standard=2, full=judgment);
  residual non-blocker findings are recorded (`gate-residual-` gotchas) and
  named in the verdict + PR body, never iterated past the depth; a confirmed
  blocker is NOT READY at any depth.
- The conclude rule: a dry round (`new_confirmed_major == 0`) ends
  light/standard iteration immediately; full needs two consecutive dry
  rounds, or one plus a recorded `--conclude-reason` — never a change to
  the pass/fail/escalate verdict contract.
- Low intent-confidence from repo-dossier-onboard status downgrades READY to
  READY-WITH-CAVEAT.
- On READY: `marshal pr` opens a PR (merge held); operator arbitrates.
- On HOLD/NOT READY: no PR; outcome surfaces via `marshal slack-send` (operator channel).
- Final message always carries: "human review still required — NOT a safety guarantee."

## Next

- **Operator action**: review the surfaced outcome, examine per-critic findings,
  and decide to approve/merge the PR or address the HOLD reason.
- **Skill**: `cross-provider-debate` — for standalone CPD on a single load-bearing
  architectural decision outside the ready-to-pr gate.
- **Skill**: `attended-slack-watch` — to continue the engagement watch cycle after
  the PR is reviewed and the next client message arrives.
