---
name: project-security-bootstrap
description: |
  Verify a new (or existing) project's security baseline before real
  implementation work starts: confirm `.gitignore` covers the sensitive-
  file patterns it should, scan the project's current state for anything
  already leaked, and — for projects that touch money, bank/ledger
  reconciliation, or personal data — hard-require `ai-governance-audit`
  and `bank-reconciliation-patterns` before proceeding. Use at the start of
  any new project, or the first time you're asked to work on an existing
  one that hasn't been checked yet.
  Do NOT use for: re-running the same check repeatedly in one session once
  it's passed and nothing has changed; auditing code quality/vulnerabilities
  in application logic (use the `security` agent for that); or rotating/
  remediating a secret that's already leaked (that's a halt-and-ask
  conversation with the user, not something this skill automates — see
  CLAUDE.md's "Security & data-privacy baseline").
---

# Project Security Bootstrap

A leak is cheaper to prevent than to clean up. This skill is the gate
between "let's start building" and actually writing code: it confirms the
project's `.gitignore` is real coverage (not a guess), that nothing is
already leaked, and — for finance/PII work — that governance is designed
in from the start rather than bolted on later.

This is the mechanical backing for the "Security & data-privacy baseline"
section of the global `CLAUDE.md`. See
`docs/plans/security-data-privacy-baseline/spec.md` in this repo for the
full design rationale, including what the underlying scan does and does
not catch.

## Step 1 — Check `.gitignore` coverage

Read the target project's `.gitignore` (or note that it's missing
entirely — that's a finding on its own, not a soft failure). Compare it
against this baseline pattern list:

```
.env*  *.key  *.pem  *credentials*  *.tfstate
.aws/credentials*  *.p12  *service-account*.json
```

This list is deliberately generic (secrets/credentials shapes, not
stack-specific ignores like `node_modules/`) — extend it with whatever the
project's actual stack needs (e.g. `*.tfvars` for Terraform-heavy
projects, `local.settings.json` for Azure Functions) rather than treating
it as exhaustive.

Report exactly which patterns are missing, one by one — "the `.gitignore`
looks incomplete" is not an acceptable output here; name the specific gap
(e.g. "`.aws/credentials*` is not excluded").

**Never edit the target project's `.gitignore` yourself without asking
first** — per this repo's own "don't touch what you didn't create,
without asking" rule. Propose the exact diff and wait for a go-ahead,
unless you created this project in the current session.

## Step 2 — Scan for what's already there

Run the same pattern set the commit-blocking hook uses — don't
reimplement it:

```bash
bash ~/.claude/hooks/secret-scan.sh --scan-path <target-project-dir>
```

This never blocks or modifies anything; it prints `CLEAN: ...` or one
`FINDING:`/finding line per hit. Any finding here is a leak that already
happened — treat it as a halt-and-ask event per CLAUDE.md's baseline
(rotation/history-rewrite is the user's call, not something to
auto-remediate), not something to silently fix and move past.

This step matters even for a project the commit hook has been protecting
from day one: the hook is blind to anything that didn't go through the
Bash tool's `git commit`/`add`/`push` shape (a secret introduced via
`git commit-tree`/`update-ref` plumbing, an MCP-based publish path, or
simply a project that existed before this tooling did) — this scan is the
catch-up layer for exactly that gap.

## Step 3 — Determine if this is a financial/PII-handling project

Check for an explicit statement from the user, or a keyword match against
the project's brief/README/task description: **reconciliation, ledger,
payment, bank, PII, personal data**. This list is a starting heuristic,
not exhaustive — if it's genuinely ambiguous whether the project touches
money or personal data, ask the user rather than guess either way.

If yes: state plainly, as a hard requirement and not a suggestion, that
`ai-governance-audit` and `bank-reconciliation-patterns` (the latter only
if the project involves transaction/ledger matching specifically) must be
invoked before implementation proceeds. This mirrors how `durable-plan` is
already mandatory for large work in this repo's CLAUDE.md — don't soften
it to "consider using" for a project that clearly qualifies.

If the project also collects or stores personal data more broadly (not
just financial), note that a privacy/data-handling note — what's
collected, where it's stored, who can see it, how long it's kept — is
part of that project's own deliverable per CLAUDE.md, not an afterthought
to add later.

## Step 4 — Report

Produce a short pass/fail summary:

```
## Security bootstrap — <project>

.gitignore: PASS | FAIL (missing: <patterns>)
Existing leaks: CLEAN | <N findings, listed>
Financial/PII: not applicable | MANDATORY — invoke ai-governance-audit
  [+ bank-reconciliation-patterns] before implementation proceeds
```

Don't proceed to implementation on a FAIL or a MANDATORY line without the
user's acknowledgment — this is the gate, not a formality to note and move
past.
