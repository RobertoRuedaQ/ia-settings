---
name: textract-document-intelligence
description: |
  Textract → Bedrock document extraction pipelines: handling low-confidence
  OCR, structuring extracted data, and routing uncertain extractions to human
  review. Use when building or reviewing an intake-document pipeline
  (invoices, forms, scanned PDFs) that combines Textract extraction with
  Bedrock for structuring/interpretation.
  Do NOT use for: the orchestration/state-machine layer around the pipeline
  (use `bedrock-agentic-workflows`), financial transaction matching (use
  `bank-reconciliation-patterns`), or the approval/audit mechanics for what
  happens after extraction (use `ai-governance-audit`).
---

# Textract + Bedrock Document Intelligence

Textract gets you raw text/structure with confidence scores; Bedrock turns
that into structured, business-meaningful data. Treat the confidence score
as a first-class signal, not something to discard after the OCR step.

## Core Rules

- **Use the right Textract API for the document.** `DetectDocumentText` for
  plain text; `AnalyzeDocument` with `FORMS`/`TABLES` for structured
  documents; `AnalyzeExpense`/`AnalyzeID` for their specific document types
  when applicable — don't reach for a generic OCR-then-LLM-parses-everything
  approach when Textract already has a purpose-built extractor.
- **Carry the confidence score through the whole pipeline.** Textract's
  per-field confidence should attach to the record all the way to the
  human-review queue — a downstream reviewer needs to know which fields
  Textract was unsure about, not just the final extracted value.
- **Bedrock structures and interprets; it does not re-OCR.** Feed Bedrock
  Textract's already-extracted text/fields to normalize and map into your
  schema — don't hand Bedrock a raw image and ask it to both read and
  interpret when Textract already did the reading more reliably and cheaper.
- **Low confidence routes to a human, it doesn't get silently accepted or
  silently dropped.** Define an explicit confidence threshold (from the
  brief/stakeholder, not guessed) below which a field is flagged for review.

## Pipeline Shape

1. **Ingest** — document lands in S3 (intake bucket), triggers the pipeline
   (S3 event → Lambda/Step Functions, not polling).
2. **Extract** — call the appropriate Textract API; get back text/fields
   with per-field confidence scores.
3. **Structure** — Bedrock maps Textract's raw fields into your target
   schema (e.g. "this blob of text is the vendor name, this one is the
   invoice total"), using the extracted text as its input, not the raw image.
4. **Score & route** — combine Textract's confidence with any
   structuring-step confidence signal; fields below threshold get flagged.
5. **Review or commit** — low-confidence fields go to human review (see
   `ai-governance-audit` for the approval workflow); high-confidence records
   commit automatically.
6. **Audit** — log what was extracted, at what confidence, and whether a
   human corrected it — this feeds both compliance and the eval harness
   (`ai-eval-cost-framework`).

## Handling Low Confidence

- Don't average away per-field confidence into one document-level score —
  a document can have one bad field and nine good ones; auto-accept the
  nine, flag the one.
- Track which fields are chronically low-confidence across documents (e.g.
  handwritten amounts, faded stamps) — that's a signal to adjust the
  pipeline (different Textract API, additional preprocessing, or accepting
  that field always needs human review), not something to re-litigate
  per-document.
- Never let a low-confidence extraction silently become an auto-committed
  value with no trace that it was uncertain.

## Testing

- Golden set of documents covering: clean digital PDF, scanned/skewed
  document, low-quality/handwritten fields, and a document missing an
  expected field entirely — assert confidence scoring and routing behave
  correctly for each.
- Test the threshold boundary explicitly (just above/below the
  auto-accept cutoff).
- Test idempotency: re-processing the same document doesn't duplicate
  committed records.

## Red Flags

- Confidence scores computed by Textract but discarded before the review
  queue.
- Bedrock asked to read the raw image when Textract already extracted the
  text — redundant cost and a worse error mode.
- A fixed confidence threshold picked without stakeholder sign-off,
  silently auto-committing extractions the business would want reviewed.
- No mechanism to notice a field type is chronically unreliable across many
  documents.
