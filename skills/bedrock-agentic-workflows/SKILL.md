---
name: bedrock-agentic-workflows
description: |
  Orchestrate agentic AI workflows on AWS Bedrock with Step Functions and
  Lambda, including mandatory human-approval points. Use when building or
  reviewing a multi-step LLM-driven automation (e.g. an agent that proposes
  an action and needs a human to confirm it), Step Functions state design
  for an AI pipeline, or Bedrock invocation patterns from Lambda.
  Do NOT use for: designing the state machine's overall architecture at
  high-complexity/multi-service scale (route to `aws-ai-engineer-max`),
  document extraction specifically (use `textract-document-intelligence`),
  or the approval/audit mechanics themselves (use `ai-governance-audit`).
---

# Bedrock Agentic Workflows

An "agent" here means a Step Functions state machine that calls Bedrock at
decision points, not an unbounded autonomous loop. Bound every step,
especially the ones a human is meant to approve.

## Core Rules

- **Explicit states, not a single do-everything Lambda.** Each meaningful
  decision (propose, validate, request approval, commit) is its own state —
  this is what makes the workflow debuggable, auditable, and resumable after
  a failure, instead of an opaque function that either fully succeeds or
  fully fails.
- **Human-approval points are real wait states**, not advisory
  notifications. Use `.waitForTaskToken` and only proceed on an explicit
  `SendTaskSuccess`/`SendTaskFailure` — see `ai-governance-audit` for the
  approval-workflow specifics.
- **Bound every loop.** An agentic step that can call itself or retry needs
  an explicit max-iteration count and a defined behavior when it's hit
  (fail to a human, not silently loop forever).
- **Bedrock calls are a state, not a side effect buried in application
  code** — make the model call, its inputs, and its output a visible,
  loggable unit in the state machine, so a failure or a governance question
  ("what did the model actually see") has a clear answer.

## Step Functions Design for AI Pipelines

- Typical shape: `Normalize input → Invoke Bedrock (propose) → Validate/
  score confidence → Choice (auto-accept | request human approval) →
  [Wait for approval] → Commit → Audit log`.
- Use `Retry`/`Catch` on the Bedrock invoke state for throttling
  (`ThrottlingException`) with exponential backoff — don't hand-roll retry
  logic in Lambda when Step Functions already does this declaratively.
- Keep state machine definitions in version control alongside the Lambda
  code they orchestrate — a state machine change is a code change, review it
  the same way.
- Pass the minimum data needed between states (an ID, not the full payload)
  when the full payload is large or sensitive — fetch it fresh in the state
  that needs it, keyed by the ID, rather than threading a big/sensitive
  object through the whole execution history (Step Functions execution
  history is not the place for raw PII).

## Bedrock Invocation from Lambda

- One Lambda per logical step, not one mega-Lambda handling every state —
  matches the "explicit states" rule above and keeps cold-start/timeout
  budgets predictable per step.
- Set explicit `max_tokens` and timeouts on every Bedrock call (see
  `ai-eval-cost-framework` for the cost side of this).
- Structure the prompt so the model's output is directly parseable
  (structured output / JSON mode where the model supports it) — don't rely
  on regex-scraping free text out of a conversational response.
- Version prompts explicitly (a prompt ID/version string logged with every
  call) so a behavior change can be traced to the prompt that caused it.

## Testing

- Test the state machine's Choice/branching logic directly (Step Functions
  local testing or a unit test against the ASL definition), not only the
  Lambda functions in isolation — the wiring between states is where bugs
  hide.
- Test the approval-timeout and max-iteration-exceeded branches explicitly.
- Mock Bedrock responses for fast, deterministic tests; reserve real Bedrock
  calls for the eval harness (`ai-eval-cost-framework`), not the CI test suite.

## Red Flags

- A single Lambda that calls Bedrock, decides, and commits with no visible
  intermediate states — undebuggable and unauditable by construction.
- An agentic loop with no max-iteration bound.
- A human-approval step implemented as a notification with the workflow
  proceeding regardless of the response.
- Raw PII threaded through Step Functions execution input/output instead of
  passed by reference.
