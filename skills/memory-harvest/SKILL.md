---
name: memory-harvest
description: |
  Sweep this project's persistent memory files for anything that should be
  promoted into committed, team-visible documentation instead of staying
  invisible in this-machine-only memory — and prune what's gone stale. Use
  periodically (end of a long session, several new memory files since the
  last sweep) or right after a debugging/decision session that produced new
  memory writes.
  Do NOT use for a single fact right after writing it — the write itself is
  enough; this is the batched review-and-promote pass, not a per-fact ritual.
---

# Memory Harvest

Session/project memory is per-machine and invisible to anyone else working
on the repo — a teammate, a fresh session, a different machine. This skill
is the periodic pass that decides what's durable enough to graduate out of
it, and what's gone stale enough to delete.

## Step 1 — Read what's there

Read the project's memory index (`MEMORY.md`) and every linked memory file
under the project's memory directory.

## Step 2 — Classify each entry

- **Gotcha** — a durable technical trap. Worth a code comment at the exact
  spot it bites, or an entry in a project `docs/gotchas.md` if there's no
  single right spot for a comment.
- **Pattern** — a confirmed, repeatable way of working for this repo. Worth
  a line in `CONTRIBUTING.md`, an architecture doc, or the project's
  `CLAUDE.md` — wherever the repo already documents conventions.
- **Dossier fact** — describes the project's scope, constraints, or a
  decision the team made. Belongs in the README or project docs, not only
  in memory.
- **Machine-local** — genuinely specific to this operator's environment (a
  local path, a personal tooling preference). Leave it in memory; it isn't
  promotion material.
- **Stale/superseded** — contradicted by the current code or since fixed.
  Flag for deletion. On a genuine conflict between what the memory says and
  what the code does, the code wins unless the memory records a
  product/business decision the code can't express by itself.

## Step 3 — Propose before writing

Present the classification as a list — what you'd promote, where, and what
you'd delete as stale — and get confirmation before touching any committed
file. Nothing gets written or deleted without the operator agreeing to the
specific list; this mirrors the "don't touch what you didn't create without
asking" discipline for anything already committed.

## Step 4 — Promote and prune together

On approval:
- Write each promoted entry into the destination the operator confirmed,
  in that doc's own voice and format — don't paste the memory file's
  frontmatter or internal shape into a human-facing doc.
- Delete or clearly mark superseded the memory file(s) that got promoted,
  so the fact isn't now duplicated (and divergeable) in two places.
- Delete the memory files confirmed stale.
- Leave machine-local entries untouched.

## Step 5 — Note what didn't move

If something looked promotion-worthy but you're not confident it's still
true, say so instead of silently promoting or silently dropping it — an
uncertain fact belongs in the "ask the operator" pile, not in either
destination.
