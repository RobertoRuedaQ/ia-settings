---
name: bank-reconciliation-patterns
description: |
  Match/break logic for reconciling financial transactions across two ledgers
  (e.g. bank statement vs. internal records) before a full ERP integration
  (Sage) exists. Use when building or reviewing transaction-matching rules,
  break/exception handling, or confidence scoring for automated matches.
  Do NOT use for: general accounting/ERP integration work once Sage is live
  (that's a different, larger scope), non-financial matching problems, or the
  governance/approval layer around a match decision (use
  `ai-governance-audit`).
---

# Bank Reconciliation — Match/Break Patterns

Reconciliation is a matching problem with a long tail of exceptions. Ship the
deterministic matcher first — it clears most of the volume cheaply — and
treat the LLM as the tool for the ambiguous remainder, not the default path
for every transaction.

## Core Rules

- **Deterministic matching first.** Exact amount + date + reference-number
  match is free, fast, and needs no model. Run it before anything
  LLM-driven — most transactions should never reach an LLM call.
- **Tiered matching, not one big model call.** Exact match → fuzzy
  rule-based match (amount tolerance, date window, normalized description
  similarity) → LLM-assisted match only for what's left. Each tier should
  clear a large chunk of volume before the next one runs.
- **A "break" is a first-class outcome, not a failure.** Unmatched
  transactions get logged with why they didn't match (no candidate in
  window, multiple ambiguous candidates, amount mismatch) — that reason
  drives what a human reviewer looks at first.
- **This runs before Sage integration exists.** Assume the "internal
  records" side is whatever interim source the brief specifies (a CSV
  export, a temporary table) — don't design against Sage's schema before
  that integration is real; keep the ledger-adapter boundary thin and
  swappable.

## Matching Pipeline

1. **Normalize both sides first.** Dates to one timezone/format, amounts to
   the same currency/precision, descriptions lowercased and whitespace/punct
   normalized — most false "no match" results are normalization bugs, not
   genuinely unmatched transactions.
2. **Exact match pass.** Same amount, same date (or within a same-day
   window accounting for settlement lag), matching reference number where
   available. Mark matched, remove from both pools, move on.
3. **Fuzzy rule-based pass.** Amount within a configured tolerance
   (basis-points or fixed threshold — get this number from the brief, don't
   guess), date within a wider window (e.g. ±3 business days for
   settlement lag), description similarity above a threshold (token overlap
   or edit distance — deterministic, not an LLM call).
4. **LLM-assisted pass (only the remainder).** For transactions with
   multiple plausible candidates or ambiguous descriptions, use Bedrock to
   propose the best match **with a confidence score and stated reasoning**
   — never a bare "yes/no". Load `ai-eval-cost-framework` before wiring this
   in: this is exactly the kind of step that should run on a smaller model
   tier, not the biggest one available.
5. **Confidence-gated auto-accept.** Only auto-commit a match above a
   deliberately chosen confidence threshold; everything else queues for
   human review via the approval workflow in `ai-governance-audit`. The
   threshold is a business decision — get it from the brief/stakeholder,
   don't pick an arbitrary number and ship it.

## Break Handling

- Every unmatched transaction gets a structured reason: `no_candidate`,
  `multiple_candidates`, `amount_mismatch`, `low_confidence`,
  `date_out_of_window`. This reason is what a human reviewer triages by —
  an undifferentiated pile of "unmatched" is not useful.
- Track break age (how long a transaction has sat unmatched) — a growing
  backlog of old breaks is a signal the matching rules need tuning, not
  that the humans need to work faster.
- Breaks are not silently retried forever on the same rules — a periodic
  re-match pass after normalization/threshold tuning is fine; an unbounded
  retry loop on unchanged inputs isn't.

## Testing

- Golden set of transaction pairs covering: exact match, off-by-one-day
  settlement lag, amount rounding, duplicate/ambiguous candidates, and
  genuinely unmatched transactions — assert each lands in the right tier
  and produces the right break reason when applicable.
- Test the confidence threshold boundary explicitly (just above / just
  below auto-accept).
- Test idempotency: re-running the matcher on already-matched transactions
  doesn't re-match or duplicate audit entries.

## Red Flags

- Every transaction going through an LLM call, including exact matches that
  a deterministic rule would catch for free.
- A confidence threshold picked without stakeholder input, silently
  auto-accepting matches the business would want reviewed.
- Break reasons that aren't captured, leaving reviewers to re-derive why
  something didn't match.
- Matching logic hardcoded against Sage's schema before that integration
  exists.
