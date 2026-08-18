---
name: kpi-nl-dashboard
description: |
  Executive KPI dashboards and natural-language reporting — the "morning
  coffee report" pattern: plain-language summaries of business metrics
  generated on a schedule or on demand, backed by a queryable data source.
  Use when building or reviewing an executive-facing metrics summary, an NL
  query interface over KPI data, or a scheduled report.
  Do NOT use for: the underlying data pipeline/ETL that produces the metrics
  (that's regular data-engineering work, not covered here), financial
  transaction matching (use `bank-reconciliation-patterns`), or LLM cost/eval
  concerns for the summarization step itself (use `ai-eval-cost-framework`).
---

# KPI Dashboard & NL Reporting

An executive doesn't want a query interface — they want an answer, in plain
language, with the number to back it up. Optimize for "what does this mean"
over "here's the query result".

## Core Rules

- **Numbers come from a real query, not from the model's memory.** The LLM's
  job is to phrase and contextualize a result that was actually computed
  (SQL/aggregation against PostgreSQL or wherever the metrics live) — never
  let it "estimate" a KPI from context. If the underlying query fails or
  returns nothing, say so plainly; don't let the model fill the gap with a
  plausible-sounding guess.
- **The "morning coffee report" is a scheduled summary, not a chatbot.**
  Default shape: a small set of KPIs, computed on a schedule (EventBridge
  scheduled rule → Lambda), summarized in plain language, delivered where
  the executive already looks (email/Slack) — not a dashboard they have to
  remember to open.
- **NL query is additive, not a replacement for the fixed report.** Offer
  natural-language ad-hoc questions on top of the same queryable metrics
  layer, but the recurring report should not depend on someone remembering
  to ask.
- **State uncertainty and context, not just the number.** "Revenue is up 12%
  week-over-week, driven mostly by a single large account — excluding it,
  growth is roughly flat" beats a bare "+12%" that invites a wrong
  conclusion.

## Building the Pipeline

1. **Metrics layer** — a small set of well-defined, pre-aggregated queries
   (a view or materialized query against PostgreSQL/RDS) that produce the
   actual KPI values. Define these explicitly; don't let the LLM construct
   ad-hoc aggregations against raw tables for the recurring report.
2. **NL query layer (for ad-hoc questions)** — when supporting natural-
   language questions over the data, constrain the model to a fixed set of
   approved query templates/views rather than generating arbitrary SQL
   against production tables — arbitrary LLM-generated SQL against a real
   database is a correctness and security risk, not just a nice-to-have
   safeguard.
3. **Summarization** — feed the computed numbers (not raw table dumps) to
   Bedrock with a prompt that asks for a short, plain-language summary
   highlighting what changed and why it might matter — cap output length,
   this is a briefing, not an essay.
4. **Delivery** — scheduled trigger (EventBridge) → compute → summarize →
   deliver (SES/Slack) → log what was sent for audit purposes.

## Communicating to Non-Technical Executives

- Lead with the takeaway, then the number, then (if relevant) the caveat —
  not the other way around.
- Avoid ML/AI jargon in the delivered report entirely — "the model flagged
  this as uncertain" becomes "this number is a preliminary estimate,
  pending review".
- When a KPI depends on a Phase 1 workflow still maturing (e.g.
  reconciliation match rate), say so — don't present an early-stage number
  with the same confidence as a mature, audited metric.

## Testing

- Test that the summarization step never runs without a real computed
  value behind it (no code path where a query failure still produces a
  plausible-looking summary).
- Test the NL-query layer's query-template constraint explicitly — a
  question that would require an unapproved query should be declined, not
  silently generate one.
- Golden set of before/after metric pairs → assert the generated summary's
  direction (up/down/flat) matches the actual data, at minimum.

## Red Flags

- A KPI number that came from the model's own reasoning instead of a
  computed query result.
- An NL-query interface that lets the model generate and run arbitrary SQL
  against production tables.
- A report that hides uncertainty on an early-stage metric behind
  confident-sounding language.
- The recurring executive report depending on someone remembering to
  trigger it manually.
