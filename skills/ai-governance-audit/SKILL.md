---
name: ai-governance-audit
description: |
  Audit logging, human-approval workflows, model cards, and runbooks for
  production AI/AWS systems in regulated environments. Use when a workflow
  acts on financial data, schedules or triggers an action, extracts PII from
  documents, or makes a decision an executive/compliance team will ask about
  later. Covers the governance layer, not the AI logic itself.
  Do NOT use for: non-AI/non-regulated projects, pure model-quality
  evaluation or cost control (use `ai-eval-cost-framework`), or the
  underlying orchestration mechanics (use `bedrock-agentic-workflows`).
---

# AI Governance & Audit

Governance is not a compliance checkbox added at the end — it's part of the
design of any workflow that touches money, PII, or an irreversible action.
Build it in from the first commit.

## Core Rules

- Every workflow that mutates financial data, schedules something, or acts
  on extracted document data logs an audit entry: **who/what triggered it,
  what action was taken, what changed (before/after), when, and the
  workflow/execution ID** that ties it back to a Step Functions run.
- Any action with real-world effect that the brief marks as needing a human
  in the loop gets a genuine approval gate — not a notification the human
  can ignore while the system proceeds anyway.
- A model card exists for every LLM-driven decision point before it ships,
  not after someone asks "how does this actually work".
- A runbook exists for every production workflow before it ships — if
  on-call can't operate it without you, it isn't done.
- Governance artifacts live in `docs/technical/<deliverable>/` and, where
  they affect what the client sees or approves, in
  `docs/client/<deliverable>/` in plain language — update them in the same
  task that introduces the behavior they describe.

## Audit Logging

Minimum fields per entry (structured, one JSON object per line or row):

```
{
  "timestamp": "...",
  "workflow": "bank-reconciliation",
  "execution_id": "<Step Functions execution ARN>",
  "actor": "system | <human approver id>",
  "action": "match_proposed | match_approved | match_rejected | ...",
  "resource": "<transaction id / document id>",
  "before": { ... },   // omit or redact fields that shouldn't be logged in plaintext
  "after": { ... },
  "reason": "optional — why a human overrode a system decision"
}
```

- Redact/encrypt PII and financial account numbers in the log itself — the
  audit log is not exempt from the same data-handling rules as the primary
  system.
- Write to a destination CloudTrail/CloudWatch already covers, or an
  explicit table (RDS/DynamoDB) if the audit trail needs to survive log
  retention limits or needs to be queryable for compliance requests.
- Log the decision **and** the inputs that produced it (which Bedrock model,
  which prompt version, which extraction confidence score) — "the system
  said so" is not an answer compliance will accept without the trail behind it.

## Human-Approval Workflows (Step Functions)

- Use the `.waitForTaskToken` pattern: the state machine pauses, sends the
  task token to the approver (SES/SNS/Slack), and only resumes on an
  explicit `SendTaskSuccess`/`SendTaskFailure` call — never a fire-and-forget
  notification with the workflow proceeding regardless.
- Always set a timeout on the wait state, with an explicit fallback (escalate
  to a second approver, or fail safely — never silently auto-approve on
  timeout unless the brief explicitly says that's acceptable).
- Log the approval/rejection itself as an audit entry (who approved, when,
  any comment) — the approval trail is often what compliance actually audits.
- Make the approver's decision surface **why** the system is asking — show
  the extracted data, the confidence score, the proposed action — not just
  "approve? y/n".

## Model Cards

One per LLM-driven decision point, kept next to its technical doc
(`docs/technical/<deliverable>/model-card.md`). Minimum sections:

- **Model & version** — e.g. Claude on Bedrock, model ID, prompt version.
- **Intended use** — the specific decision this model makes, and what it
  explicitly does *not* decide (e.g. "extracts a proposed match; a human
  approves or rejects it — the model does not commit the reconciliation").
- **Known limitations** — failure modes observed in eval or production
  (low-confidence extraction on handwritten documents, sensitivity to
  Textract OCR errors, etc.).
- **Evaluation summary** — link to the eval harness results (see
  `ai-eval-cost-framework`) and the date they were last refreshed.
- **Last reviewed** — date and who reviewed it. A stale model card is a
  governance gap, same as a missing one.

## Runbooks

One per production workflow (`docs/technical/<deliverable>/runbook.md`).
Minimum sections:

- **What it does** — one paragraph, plain enough for on-call at 2am.
- **How to run it manually** — the exact command/console steps to trigger
  or re-trigger the workflow outside its normal trigger.
- **How to check its health** — which CloudWatch dashboard/alarm, which log
  group, what "healthy" looks like.
- **Common failure modes** — the 2-3 most likely things to go wrong and the
  fix for each (throttled Bedrock call, stuck approval wait state, Textract
  low-confidence spike).
- **Rollback** — how to disable or roll back the workflow without touching
  a shared/production datastore directly (per this environment's
  halt-and-ask discipline for infra changes).
- **Who to page** — even if it's just "the person who built this" for now.

## Testing

- Assert an audit entry is written for every state-changing action in the
  workflow's test suite, not just the happy path.
- Test the approval-timeout branch explicitly — don't only test the
  approve/reject paths.
- Treat "the model card is missing/stale" and "the runbook doesn't exist"
  as blocking findings in review, same severity class as a missing test.

## Red Flags

- An irreversible action (payment, scheduled commitment, data deletion)
  with no approval gate, when the brief calls for one.
- Audit log storing PII/account numbers in plaintext.
- A `.waitForTaskToken` wait state with no timeout.
- A model card that doesn't exist, or exists but predates the last prompt
  change.
- A production workflow with no runbook — "ask the person who built it" is
  not a runbook once that person is unavailable.
- Approval UX that doesn't show the approver what they're actually approving.
