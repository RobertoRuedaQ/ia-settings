# Claude Code environment (compact)

Global `~/.claude` config: agents, skills, hooks, `settings.json`. Three
domains — Rails/Ruby, React/Next.js, Python/AWS AI — plus stack-agnostic
tools. Only `agents/`, `skills/`, `hooks/`, `CLAUDE.md`, `settings.json`
are tracked in git; everything else (incl. `docs/`) stays local.

## Agents — daily-driver (Sonnet) + high-complexity (Opus) per domain

- **Rails**: `dhh` / `dhh-max`.
- **React/Next.js**: `frontend` / `frontend-max`.
- **Python/AWS AI**: `aws-ai-engineer` / `aws-ai-engineer-max` (Bedrock,
  Textract, Lambda, Step Functions; `-max` for state-machine design,
  IAM/security decisions, EKS).
- **Cross-stack**: `security` (Rails+JS+Python/AWS OWASP review),
  `tech-lead` (mentoring), `pm` (cost/ROI), `skeptic` (adversarial
  claim-checking — invoke before treating a diagnosis/"done"/"safe" as settled).

## Skills (loaded mid-task by the matching agent)

- **Rails**: `idiomatic-rails-patterns`, `ruby-design-rules`, `rails-init`,
  `rails-migrations`, `rails-security-multitenancy`, `rails-webhooks`,
  `rails-hotwire-realtime`, `background-job-designer`, `test-writer`.
- **Frontend**: `vercel-react-best-practices`, `vercel-composition-patterns`,
  `vercel-react-view-transitions`, `web-design-guidelines`.
- **AWS AI**: `ai-governance-audit` (audit log, human-approval, model
  cards, runbooks), `ai-eval-cost-framework` (eval harness, model
  tiering, cost), `bank-reconciliation-patterns`, `bedrock-agentic-workflows`,
  `textract-document-intelligence`, `kpi-nl-dashboard`.
- **Meta**: `durable-plan` (spec+plan to disk for 3+ file work),
  `memory-harvest` (promote/prune persistent memory).

## Hooks (wired in `settings.json`)

- `plan-orientation.sh` (`SessionStart`) — surfaces open plan tasks.
- `plan-statusline.sh` (`statusLine`) — plan progress in the status line.
- `token-cost-report.sh` (`Stop`/`SubagentStop`) — tokens + $ cost per task.
- `learnings-capture.sh` (`Stop`/`SubagentStop`) — captures ` ```learning `
  fenced blocks into `docs/learnings/LEARNINGS.md` automatically.
- Plus a `PreToolUse` Bash audit log and a `Notification` terminal beep.

## `settings.json`

Deny-list blocks destructive commands (`rm -rf`, force-push, `reset --hard`,
`DROP TABLE`) and edits to sensitive files — Rails (`Gemfile`, schema,
initializers, credentials, `.env`) and AWS (`~/.aws/credentials*`,
`*.tfstate`, `cdk.out/**`).

## Flow

Pick agent by domain/complexity → agent loads its skill(s) before coding →
`durable-plan` for anything 3+ files/multi-session → `learnings-capture.sh`
+ `token-cost-report.sh` fire automatically at Stop → `memory-harvest`
periodically promotes durable facts into committed docs.

Full detail: `README.md`. AWS AI design rationale:
`docs/plans/aws-ai-engineer-env/{spec,plan}.md` (local-only).
