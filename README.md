# Claude Code environment

This repo is Roberto's global `~/.claude` configuration: subagents, skills,
hooks, and permission/hook wiring in `settings.json`. It spans three
domains today — Ruby on Rails, React/Next.js frontend, and Python/AWS AI —
plus a set of domain-agnostic tools (planning, memory, review) that apply
regardless of stack.

Only `agents/`, `skills/`, `hooks/`, `CLAUDE.md`, and `settings.json` are
tracked in git (see `.gitignore`) — everything else under `~/.claude`
(transcripts, caches, local plans in `docs/`, machine state) stays local.

## Agents

Each domain follows the same **daily-driver (Sonnet) + high-complexity
(Opus)** split: the Sonnet tier handles routine, single-file work and
explicitly routes to its Opus sibling once a task crosses a complexity bar
(multi-file/architectural change, or a sensitive file). This keeps cost
proportional to the work — most tasks never need the Opus tier.

| Agent | Model | Domain | Use for |
|---|---|---|---|
| `dhh` | Sonnet | Rails/Ruby | Daily-driver Rails work — single-file changes, bug fixes, query tuning, standard model/controller/view edits, tests. |
| `dhh-max` | Opus | Rails/Ruby | High-complexity Rails — multi-file/architectural changes, new feature design, or edits to sensitive files (`config/initializers`, schema, `Gemfile`, shared base classes). |
| `frontend` | Sonnet | React/Next.js | Daily-driver frontend — components, pages, perf/a11y review, animations. Delegates to the installed Vercel skills rather than improvising. |
| `frontend-max` | Opus | React/Next.js | High-complexity frontend — multi-file refactors, new shared components/design-system primitives, or sensitive config (`next.config`, middleware, root layout). |
| `aws-ai-engineer` | Sonnet | Python/AWS AI | Daily-driver AI/AWS work — Bedrock/Textract/Lambda calls, agentic workflows, iterating on an MVP. Ships fast, bakes in governance/cost-awareness by default. |
| `aws-ai-engineer-max` | Opus | Python/AWS AI | High-complexity AI/AWS — Step Functions state-machine design, multi-service orchestration, IAM/security-policy decisions, cost-architecture tradeoffs, EKS. |
| `security` | Sonnet | Rails, React/JS/TS, Python/AWS | Security reviewer — OWASP-class issues, IAM/Cognito/KMS misconfig, secrets, SSRF/injection. Runs `git diff`, returns a severity-ranked report. |
| `tech-lead` | Sonnet | Any | Growth-oriented mentor — SOLID/DRY/KISS in context, teaches through questions, small refactor + thought-prompt. |
| `pm` | Sonnet | Any | Cost/product coach — token/LLM spend, infra cost, build-vs-buy, quantifies impact in dollars/hours. |
| `skeptic` | Sonnet | Any | Adversarial reviewer for **claims**, not code style — pressure-tests a root-cause diagnosis, a "this is safe/done" statement, or a decision made with no dissent before it's treated as settled. |

## Skills

Skills are progressive-disclosure references an agent loads mid-task —
domain conventions, checklists, and patterns too detailed to keep in every
system prompt.

**Rails/Ruby** — loaded by `dhh`/`dhh-max`:
- `idiomatic-rails-patterns` — 37signals/Basecamp conventions: concerns over service objects, state-as-records, DB constraints over AR validations.
- `ruby-design-rules` — Sandi Metz's POODR rules (class/method size, parameter count).
- `rails-init` — structured onboarding: Gemfile → schema → routes → initializers.
- `rails-migrations` — safe, reversible, lock-aware migrations; Sidekiq for backfills.
- `rails-security-multitenancy` — scoped queries, three-layer auth, SSRF defenses, tenant isolation.
- `rails-webhooks` — inbound/outbound webhook delivery, retries, signature verification.
- `rails-hotwire-realtime` — Turbo Streams/Frames, Stimulus, ActionCable broadcast patterns.
- `background-job-designer` — Sidekiq + Redis jobs: race-condition prevention, memory safety.
- `test-writer` — RSpec test quality (Marston & Dees, RuboCop RSpec style guide).

**React/Next.js** — loaded by `frontend`/`frontend-max`:
- `vercel-react-best-practices` — Vercel Engineering's 72 impact-ranked performance rules.
- `vercel-composition-patterns` — compound components, composition over boolean props.
- `vercel-react-view-transitions` — the View Transition API for page/route animation.
- `web-design-guidelines` — live Web Interface Guidelines for UI/a11y/UX review.

**Python/AWS AI** — loaded by `aws-ai-engineer`/`aws-ai-engineer-max`:
- `ai-governance-audit` — audit logging, human-approval (`.waitForTaskToken`) workflows, model cards, runbooks.
- `ai-eval-cost-framework` — LLM eval harnesses, model tiering, token budgeting, prompt caching.
- `bank-reconciliation-patterns` — tiered match/break logic for financial transactions.
- `bedrock-agentic-workflows` — Step Functions + Bedrock orchestration with bounded loops and real approval gates.
- `textract-document-intelligence` — Textract → Bedrock extraction pipelines, confidence-based routing to human review.
- `kpi-nl-dashboard` — natural-language executive reporting backed by real queries, never model-guessed numbers.

**Cross-cutting / meta**:
- `durable-plan` — writes a spec + task-plan pair to disk for any multi-file or multi-session unit of work, so it survives context loss.
- `memory-harvest` — sweeps this-machine-only memory for what should be promoted into committed docs, and prunes what's stale.

## Hooks

Wired in `settings.json`'s `hooks` block:

| Hook | Event | Purpose |
|---|---|---|
| `plan-orientation.sh` | `SessionStart` (startup/resume/compact) | Surfaces open `durable-plan` tasks for the active project so a fresh session or a compaction doesn't lose track of work in flight. |
| `plan-state.sh` | *(sourced helper, not a standalone hook)* | Scans `docs/plans/*/plan.md` for open/done task counts — used by `plan-orientation.sh` and `plan-statusline.sh`. |
| `plan-statusline.sh` | `statusLine` | Renders plan progress in the terminal status line. |
| `token-cost-report.sh` | `Stop`, `SubagentStop` | Reports tokens consumed + estimated USD cost for the task/subagent that just finished, model-aware (Opus/Sonnet/Haiku pricing). |
| `learnings-capture.sh` | `Stop`, `SubagentStop` | Mechanically captures ` ```learning ` fenced blocks from the assistant's final message into `<project>/docs/learnings/LEARNINGS.md` — a gotcha or confirmed decision doesn't depend on remembering to write it down. |

There's also a `PreToolUse` hook on `Bash` that appends every command to
`bash-audit.log`, and a `Notification` hook that beeps the terminal bell.

## `settings.json` highlights

- **Permission deny-list**: destructive commands (`rm -rf`, force-push,
  `git reset --hard`, `DROP TABLE`) plus edits to sensitive files —
  Rails (`Gemfile`, `db/schema.rb`, `config/initializers/**`,
  `config/application.rb`, credentials, `.env`) and AWS
  (`~/.aws/credentials*`, `*.tfstate`, `cdk.out/**`).
- **`statusLine`**: shows durable-plan progress via `plan-statusline.sh`.
- Two plugins enabled: `modern-web-guidance` (Chrome/web platform best
  practices) and `frontend-design`.

## How it fits together

1. An agent is picked (explicitly or via its `description` trigger
   conditions) for the domain and complexity of the task.
2. The agent loads the relevant skill(s) before writing code — skills are
   the source of truth for domain conventions, not the agent's own memory.
3. `durable-plan` captures anything spanning 3+ files or multiple sessions
   as a spec + task-plan pair on disk before implementation starts.
4. `learnings-capture.sh` and `token-cost-report.sh` run automatically at
   `Stop`/`SubagentStop` — no extra step required to log a gotcha or see
   what a task cost.
5. `memory-harvest` periodically promotes durable facts from this-machine
   memory into committed docs, and prunes what's gone stale.

See `docs/plans/aws-ai-engineer-env/{spec,plan}.md` (local-only, not
tracked in git) for the design rationale behind the Python/AWS AI addition
specifically.
