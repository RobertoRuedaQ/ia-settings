---
name: engagement-knowledge-harvest
description: |
  Recover engagement knowledge that agents hoarded in per-machine harness
  memory and fold it into the engagement's system of record —
  `.marshal/knowledge/` (via `marshal knowledge add`) and the dossier
  (`.marshal/context/{repo-map,brief}.md`).

  Why this exists: harness memory (e.g. a Claude Code per-project memory
  directory) dies with the machine, never reaches another operator, and is
  invisible to marshal tooling. Discipline rule 13 makes writeback mandatory
  going forward; this skill is the BACKFILL for what already leaked, and the
  periodic sweep for what still does.

  Operator-gated: nothing is written to the knowledge base or dossier without
  the operator approving the proposed entry list. Nothing in harness memory is
  ever deleted by this skill.
---

# engagement-knowledge-harvest

One run harvests ONE engagement. The flow: locate harness-memory stores →
classify each memory → propose a writeback list → operator approves → write
via the sanctioned verbs → stamp provenance.

**Invoke when:**
- `marshal knowledge status` shows activity with an empty/stale knowledge base
  (the `status` nudge names this skill);
- onboarding an engagement onto a new machine (harvest BEFORE the old machine
  is retired);
- periodically on long engagements ("sweep my memory into marshal").

---

## Step 0 — grounding + target

1. Resolve the engagement root (`marshal path`). Confirm grounding
   (`marshal onboard-status`) — the dossier must exist before facts can be
   folded into it; if ungrounded, run `marshal onboard` first and stop.
2. Print `marshal knowledge status` — this is the before-picture; the report
   in Step 5 repeats it after.

## Step 1 — locate harness-memory stores

Check, in order (list what you find; do not read yet):

1. **Claude Code per-project memory** — `~/.claude/projects/<munged-path>/memory/`
   where `<munged-path>` is the engagement root's absolute path with `/`
   replaced by `-`. Check the engagement root AND any repo subdirectories the
   operator works from (root-wraps-repo layout gives each its own store).
   `MEMORY.md` there is the index; the other `.md` files are the entries.
2. **Other harness stores the operator names** (OpenCode, editor scratch
   notes). Ask once: "any other place you or your agents keep notes on this
   engagement?"

If no store exists, report "nothing to harvest" and stop.

## Step 2 — classify every memory entry

Read each entry and classify:

| Class | Test | Destination |
|---|---|---|
| `gotcha` | A tripwire future sessions must not re-trip (surprise behavior, footgun, ordering constraint) | `marshal knowledge add --kind gotcha` |
| `pattern` | A confirmed way of working in THIS engagement (build/test/review/deploy conventions) | `marshal knowledge add --kind pattern` |
| `dossier-fact` | A fact about the client, scope, stack, or repo topology | edit `repo-map.md` / `brief.md` |
| `machine-local` | Paths, credentials pointers, personal preferences, cross-engagement notes | leave in harness memory (correct home) |
| `stale` | Contradicted by the current code/dossier — verify before classifying | propose discarding (operator decides; this skill never deletes) |

Rules:
- **Verify before folding**: a memory that names a file/flag/behavior is
  checked against the current repo first (memories record what was true when
  written). A memory that fails verification is `stale`, not `dossier-fact`.
- **Never copy secrets** or personal-infrastructure details into `.marshal/` —
  the knowledge base and dossier travel with the engagement.
- One-line entries only for gotcha/pattern; longer lore is summarized into the
  dossier with the memory as source.

## Step 3 — propose the writeback list (approval gate)

Present to the operator, verbatim, grouped by destination:

```
HARVEST PROPOSAL — <engagement>
knowledge add (gotcha):
  [GOTCHA:<label>] <text>            ← from <memory-file>
knowledge add (pattern):
  [PATTERN:<label>] <text>           ← from <memory-file>
dossier updates:
  <file>: <one-line summary of edit> ← from <memory-file>
skipped (machine-local): <count>     stale (propose discard): <list>
```

Wait for approval. The operator may strike or edit lines. Do NOT write
anything before the approval.

## Step 4 — write back

For each approved line:
- gotcha/pattern → `marshal knowledge add [target] --kind <kind> --label <label> --text "<text>"`
- fixed/disproven staged entry → `marshal knowledge deprecate [target] --kind <kind> --label <label> --reason "fixed in vX.Y.Z, PR #N"` — the retirement half of the lifecycle: retags `[DEPRECATED-…]` (ages out of grounding + candidates, block kept as history, event recorded). Sweep for these during every harvest: an entry whose bug a release has since fixed, or whose claim the code now disproves, is rot — deprecate it with the fixing release named. Never hand-edit the markdown; the verb is the audit trail.
  (the verb emits the `knowledge_update` event — the audit trail).
- dossier-fact → edit the dossier file directly, preserving its structure.

Then stamp provenance in the harvested memory files: append a single line
`<!-- harvested → .marshal/knowledge (<date>) -->` to each memory file whose
content was folded, so a future harvest run does not re-propose it. Do not
otherwise modify or delete memory files.

## Step 5 — report

```
HARVESTED — <engagement>
  written: N gotchas · M patterns · K dossier edits
  skipped: X machine-local · Y stale (left for operator)
  knowledge line (after): <output of marshal knowledge status>
```

## Next

- Skill: none — terminal.
- Why: the writeback discipline (rule 13) owns the steady state; harvest is
  the backfill/sweep.
- Input: n/a
- Skip condition: n/a
