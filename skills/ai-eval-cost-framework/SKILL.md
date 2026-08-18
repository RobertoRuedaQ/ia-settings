---
name: ai-eval-cost-framework
description: |
  Build lightweight LLM evaluation harnesses and keep Bedrock/LLM usage
  cost-conscious — token budgeting, model tiering, caching, and per-workflow
  cost visibility. Use when adding a new Bedrock-driven decision point, before
  choosing a model tier, or when a workflow's LLM cost needs to be traceable
  for the ROI story. Must-have, not nice-to-have, for every deliverable.
  Do NOT use for: full production drift/monitoring (Phase 3 —
  `mlops-drift-monitoring`, not built yet), audit logging or approval
  workflows (use `ai-governance-audit`), or general AWS cost/infra questions
  unrelated to LLM usage (use `pm`).
---

# AI Evaluation & Cost Framework

"Good enough, cheap, and measurable" beats "impressive and unaccountable".
Every LLM-driven decision point needs both a way to know it's working and a
number for what it costs — from the first prototype, not added after a
surprise AWS bill.

## Core Rules

- Before writing a prompt, know what "correct" means for this task well
  enough to write a test case for it.
- Before picking a model, check whether a cheaper tier clears the accuracy
  bar — don't default to the biggest model available.
- Every Bedrock call's token usage is logged per workflow, so cost is
  traceable back to a specific deliverable, not just a monthly AWS total.
- Eval and cost are cross-cutting: wire them in when the workflow is built,
  not as an afterthought once it's already in production.

## Evaluation Harness

- Build a small golden dataset per decision point: real (or realistic,
  anonymized) examples with known-correct outputs. A dozen well-chosen cases
  beats zero, and beats waiting for "enough" data before starting.
- Pick a scoring method that fits the output shape:
  - **Structured extraction** (amounts, dates, matched transaction IDs):
    exact-match or tolerance-based comparison against the golden answer —
    cheap, deterministic, run on every change.
  - **Open-ended text** (a summary, a KPI narrative): LLM-as-judge with a
    rubric, or a human spot-check on a sample — reserve for cases exact-match
    can't cover.
  - **Human-approval-gated decisions**: track the human override rate (how
    often a human rejects/corrects the system's proposal) as a live
    accuracy signal, not just the offline eval score.
- Re-run the harness whenever the prompt, model, or model version changes —
  a silent model upgrade is a silent behavior change.
- Keep the harness runnable in minutes, not hours — a slow eval loop doesn't
  get run before a rushed deploy, which defeats the point.

## Model Tiering

- Match the model to the task, not the other way around: simple
  classification/routing → cheapest tier that clears the accuracy bar;
  extraction/reasoning → mid tier; genuinely hard, ambiguous judgment calls →
  reserve the frontier tier, and only for the specific step that needs it.
- Don't run an entire multi-step agentic workflow on the most expensive
  model when only one step needs that capability — split the workflow so
  cost scales with actual difficulty.
- Re-evaluate tiering choices when a cheaper model ships or improves — a
  tiering decision from month 1 shouldn't go unquestioned through month 12.

## Cost Controls

- Set `max_tokens` deliberately for every call — an unbounded generation on
  a runaway loop is the most common silent cost blowup.
- Cap and back off retries explicitly; a naive infinite retry loop against a
  throttled Bedrock endpoint multiplies cost without adding value.
- Use prompt caching for repeated system prompts/context (Bedrock supports
  prompt caching for supported models) — a static instruction block
  shouldn't be billed as fresh input tokens on every call.
- Batch where the API supports it instead of one call per item, when latency
  allows it.
- Log per-call token usage (input/output/cache-read/cache-write) tagged by
  workflow and deliverable, so a monthly AWS bill can be attributed back to
  "bank reconciliation cost $X this month", not just a lump sum.

## Communicating Limitations

- When reporting eval results to executives or Compliance, state the
  accuracy number **and** what it means in practice — "94% exact-match on
  clean PDFs, drops on handwritten forms, human review catches the
  remainder" beats a bare percentage.
- Never imply higher confidence than the eval actually supports. If the
  golden dataset is small or unrepresentative, say so.

## Red Flags

- A Bedrock call with no `max_tokens` cap and no retry limit.
- A model chosen without checking whether a cheaper tier was tried first.
- An eval that only ran once, manually, before the first demo — with no
  re-run since prompt/model changes.
- Cost visibility that only exists at the AWS-bill level, with no
  per-workflow breakdown.
- An accuracy number reported to executives with no caveat about dataset
  size or known failure modes.
