---
name: repo-dossier-onboard
description: |
  The lifecycle the operator's Claude runs to POPULATE the grounding dossier for
  a Marshal engagement. Produces two authoritative grounding artifacts:
  `.marshal/context/repo-map.md` (repo-onboarding — archetype, stack, entry
  points, key files, build/test/run commands, environment needs) and
  `.marshal/context/brief.md` (context-intake — objective, scope, constraints,
  key decisions, open questions from docs/READMEs/ADRs/tickets/Slack history).
  Then surfaces the access-doctor checklist via `marshal onboard-status`.

  The dossier is the grounding the discipline layer REQUIRES. Do not begin
  implementation work until it is populated — the gate enforces it
  (`marshal_core.grounding.require_grounding` raises `NotGroundedError` and the
  watcher handler refuses to act ungrounded). Host-native, `.marshal/`-rooted;
  no container coupling; secrets resolved from env vars, not parameter stores.
---

# repo-dossier-onboard

The skill the operator's Claude runs to turn a freshly scaffolded Marshal
engagement (empty `.marshal/context/` placeholders) into a grounded one (real
repo map + real brief). Grounding is the prerequisite for autonomous work: the
**watch handler** (Step 0 of the handler prompt) calls `context_present` /
`require_grounding` and refuses to act (records a `held` ledger entry + surfaces
"run `marshal onboard`") when the engagement is ungrounded, and the watch daemon
logs an advisory warning at start. (Gating the completion panel and the amend
pipeline on grounding is *planned — not yet wired*; do not assume those paths
refuse on an ungrounded engagement today.)

> **Do not begin implementation work until the dossier is populated.** The
> grounding gate (`marshal_core.grounding.context_present` + `require_grounding`)
> enforces this mechanically: `.marshal/context/repo-map.md` and
> `.marshal/context/brief.md` must both exist with non-placeholder content before
> the watcher acts. Run `marshal onboard` to scaffold the placeholder files, then
> run this skill to fill them with real content.

## When to Invoke

- After `marshal onboard` has scaffolded `.marshal/context/` with placeholder
  files and you need to populate them with real content.
- When `marshal onboard-status` reports `grounded: false` (either file is
  missing or still contains the `<!-- MARSHAL: not yet grounded -->` marker).
- At the start of a new engagement before any other Marshal skill is invoked.
- After an amendment that materially changes the scope or stack — re-run the
  relevant steps to keep the dossier current.

Do NOT invoke when the engagement is already grounded (`context_present` returns
`True` and the content is fresh). Running when grounded is harmless but
unnecessary.

## Inputs

| Input | Source | Notes |
|---|---|---|
| Engagement root | Argument to `marshal onboard` | Absolute path; `.marshal/` lives under it. |
| Scaffolded context dir | `.marshal/context/` | Created by `marshal onboard`; files contain the placeholder marker. |
| Repository source | The engagement root's codebase | What `marshal onboard` scaffolded the engagement against. |
| Docs / READMEs / ADRs | Files in the repo or linked externally | Intake sources for the brief. |
| Tickets / Slack history | User-provided links or IDs | Optional intake sources; manual-only works when no connector is available. |
| Access config | `.marshal/config.yaml` (`access:` section) | Drives the access-doctor checklist. |

## Steps

### Step −1 — readiness preflight (advisory here, hard before any gate)

Run `marshal doctor` before any other step. The critic-dispatch checks below
are a **hard precondition for debates and gates** (cross-provider-debate, ready-to-pr-review
— no cross-family critic can run without them), but grounding itself is a
read/write documentation task that needs no critics: a red critic check does
NOT block onboarding.

```bash
marshal doctor
```

Inspect the output for the OpenCode-readiness checks:

| Check (as printed by `marshal doctor`) | What it verifies |
|---|---|
| `opencode` | The `opencode` binary is reachable in the operator's shell. |
| `critic agent` | The critic agent definition is present and readable. |
| `dual-harness` | `dual-harness.json` is present with a valid executor config. |
| `dh-dispatch self-test` | `dh-dispatch.sh` is vendored, executable, and passes its own smoke test. |

**If any critic-dispatch check is red: surface it, then proceed with
grounding — but do NOT run a debate or the review gate until it is green.**

Surface the doctor's remediation instructions to the operator. Each red check
includes an actionable fix (e.g., `brew install opencode`, path wiring,
creating `~/.config/opencode/agent/critic.md` manually as a tool-less critic
agent, then re-running `marshal doctor`). Continue to Step 0 either way —
re-run `marshal doctor` and confirm the critic-dispatch checks are green
before the FIRST debate or review gate, not before grounding.

This preflight parallels grounding as a precondition: grounding gates
implementation work; critic readiness gates debates and the review gate.

### Step 0 — Scaffold context directory (run `marshal onboard`)

Run `marshal onboard <engagement-root>` if `.marshal/context/` does not yet
exist or the placeholder files are missing. This command:

1. Creates `.marshal/context/` if absent.
2. Writes `.marshal/context/repo-map.md` with the marker
   `<!-- MARSHAL: not yet grounded -->` if the file does not yet exist or is
   empty. Preserves the file unchanged if real content is already present.
3. Writes `.marshal/context/brief.md` with the same marker under the same
   idempotency rule.
4. Runs the access-doctor and prints the checklist (see Step 3).

After this step, `context_present` returns `False` — the scaffolded placeholders
are intentionally not treated as grounded.

### Step 1 — Repo-onboarding → `.marshal/context/repo-map.md`

Map the repository. The goal is a compact, practical map calibrated to the
repo's archetype — what you "read first" for a library is not what you read first
for a Terraform repo or a microservice. Replace the placeholder marker in
`.marshal/context/repo-map.md` with the full map; preserve existing real content
on re-runs (never overwrite a non-placeholder file).

#### Step 1.1 — Identify the archetype and stack

Read top-level signals to classify the repo:

```bash
ls package.json pyproject.toml Cargo.toml go.mod pom.xml Gemfile composer.json 2>/dev/null
test -f Dockerfile -o -f docker-compose.yml -o -f compose.yml && echo "Containerized"
ls -d frontend/ backend/ apps/ services/ packages/ cli/ lib/ src/ 2>/dev/null
ls -d terraform/ infra/ k8s/ helm/ ansible/ 2>/dev/null
test -f openapi.yaml -o -f openapi.yml && echo "API spec present"
```

| Archetype | Identifying signals |
|---|---|
| **Backend service / API** | `Dockerfile`, web framework deps, `openapi.yaml`, route handler dirs |
| **Library / SDK** | Published `name` in manifest, `CHANGELOG.md`, `docs/`, no app entrypoint |
| **CLI tool** | `bin/`, `cli/`, `console_scripts` entry points, `argparse`/`click`/`cobra` deps |
| **Frontend / SPA** | `index.html`, `vite.config`/`next.config`, React/Vue/Svelte deps |
| **Data pipeline / ML** | DAG framework deps (Airflow/Dagster/Prefect), `models/`, `notebooks/` |
| **Infrastructure** | `*.tf`, `kustomization.yaml`, `Chart.yaml`, `playbook.yml` |
| **Monorepo** | `nx.json`, `turbo.json`, `pnpm-workspace.yaml`, multiple `apps/` + `packages/` |

For monorepos, run the union of relevant archetypes for the packages being worked on.

#### Step 1.2 — Find entry points

Per archetype:

- **Service:** main app file, worker/job runners, scheduled tasks.
- **Library:** the file(s) that define the public API (`__all__`, barrel exports).
- **CLI:** the binary entrypoint registered in the manifest, subcommand dispatch.
- **Frontend:** root component, router config, app shell.
- **Pipeline:** pipeline/DAG definitions, scheduled triggers.
- **Infra:** root module / chart / playbook entrypoint.

#### Step 1.3 — Map the structure

Top-level directories and what they own. For each major directory, one line:
"what code lives here" and "when you'd touch it." Identify the **load-bearing
files** — route registrations, dependency injection wiring, type definitions,
schema files. These are the contract surfaces.

#### Step 1.4 — Surface commands

The five always-asked: run, test, lint, build, dev. Pull from `package.json`
scripts, `Makefile`, `justfile`, `pyproject.toml [tool.scripts]`, CI config, or
README. **Mark each as verified** (you ran it and saw output) **or inferred**
(you read it in a manifest but haven't run it).

#### Step 1.5 — Surface environment requirements

- Required env vars (look for `.env.example`, README, config loaders).
- Local services: DB, cache, queue, search index, S3-compatible storage.
- External dependencies: third-party APIs the environment needs to reach.
- How to bootstrap a working local setup (seed data, migrations, etc.).

#### Step 1.6 — Write `.marshal/context/repo-map.md`

Write the map using this structure:

```markdown
## Repo Map

### Archetype
- <service / library / CLI / frontend / pipeline / infra / monorepo>
- Why: <signals that classify it>

### Stack
- Main languages, frameworks, and tooling

### Entry Points
- <archetype-specific entry files with paths>

### Key Commands
- run / test / lint / build / dev — actual commands (verified or inferred)

### Structure
- Important directories and what they own (one line each)
- Load-bearing contract files (registrations, DI wiring, type defs, schema)

### Environment
- Required services, env vars, local setup notes

### Read First
- 3–7 files calibrated to the archetype
```

Rules:
- Prefer concrete file paths and commands over vague architecture prose.
- Call out missing documentation or confusing setup — those are the real
  onboarding tax.
- Distinguish verified commands (you ran them) from inferred commands (you
  read them).
- 3–7 files in "Read First" is the cap. More than that is a search engine,
  not a map.

#### Step 1.7 — Repo agents → the `### Repo Agents` section

`marshal onboard` detected any `.claude/agents/*.md` the repo ships and
wrote the code-owned inventory to `.marshal/context/repo-agents.yaml`.
Author the repo-map section FROM THAT ARTIFACT — never from your own
directory listing (the artifact carries the sanitized names, byte-faithful
paths, digests, and the `inventory_incomplete` marker).

- When the artifact has `agents: []` and `inventory_incomplete: false`
  (the fully-scanned zero-agent case): OMIT the section entirely.
- When the scan was capped with zero agents inventoried: write an
  anomaly-only section — "inventory may be incomplete — enumeration
  capped" — so the anomaly never disappears from the dossier.
- Otherwise, one line per agent: name, purpose, path (render the
  artifact's `display_path` field when present — it is the pre-sanitized
  form of a path whose raw bytes would break terminal/markdown rendering;
  the raw `path` stays identity-only), and
  an `approved-for-use: yes|no` field (default `no` — mirror the event
  log, see below). Purpose comes from the artifact's `description`; when absent,
  record `(no description declared)` — NEVER fabricate one (a bounded read
  of that one agent file to summarize is permitted, but mark the summary
  as Marshal's, not the file's).

Carry this doctrine text in the section, verbatim in substance:

> These are the TEAM'S conventions — consultative, never definitive.
> In-session use via the Agent tool is OPERATOR-GATED: an agent may be
> invoked only after the operator approves it for this engagement
> (`marshal agents approve --path <path>`), and approval is verified LIVE
> immediately before every invocation by running
> `marshal agents status --path <path>` — approval is content-bound (a
> changed file voids it), and the `approved-for-use` line here is a
> display-only mirror that may be stale: the status verb, never this
> section, is the enforcement check. Unapproved or approval-void agents
> are never invoked. Every use is additionally DISCLOSED to the operator
> when it happens. Repo agents are never wired into engine dispatch.

#### Step 1.8 — Dev environment → the `### Dev Environment` section

`marshal onboard` detected the repo's development-environment surfaces —
skills (`.claude/skills/*/SKILL.md`), hooks (`.claude/settings.json` hook
definitions), and rules (`.claude/rules/*.md` / equivalent convention docs)
— and wrote the code-owned inventory to
`.marshal/context/dev-environment.yaml`. Author the repo-map section FROM
THAT ARTIFACT — never from your own directory listing (the artifact
carries the sanitized names, byte-faithful paths, digests, and the
`inventory_incomplete` marker per surface).

**Skills — mirrors the Repo Agents doctrine, operator-gated:**

- When the artifact's `skills` list is empty and `inventory_incomplete:
  false` for that surface (the fully-scanned zero-skill case): OMIT the
  skills subsection entirely.
- When the scan was capped with zero skills inventoried: write an
  anomaly-only subsection — "inventory may be incomplete — enumeration
  capped" — so the anomaly never disappears from the dossier.
- Otherwise, one line per skill: name, purpose, path (render the
  artifact's `display_path` field when present — it is the pre-sanitized
  form of a path whose raw bytes would break terminal/markdown rendering;
  the raw `path` stays identity-only), and an `approved-for-use: yes|no`
  field (default `no` — mirror the event log). Purpose comes from the
  artifact's `description`; when absent, record `(no description
  declared)` — NEVER fabricate one (a bounded read of that one skill file
  to summarize is permitted, but mark the summary as Marshal's, not the
  file's).

Carry this doctrine text in the skills subsection, verbatim in substance:

> These are the TEAM'S conventions — consultative, never definitive.
> In-session use via the Skill tool is OPERATOR-GATED: a skill may be
> invoked only after the operator approves it for this engagement
> (`marshal skills approve --path <path>`), and approval is verified LIVE
> immediately before every invocation by running
> `marshal skills status --path <path>` — approval is content-bound (a
> changed file voids it), and the `approved-for-use` line here is a
> display-only mirror that may be stale: the status verb, never this
> section, is the enforcement check. Unapproved or approval-void skills
> are never invoked. Every use is additionally DISCLOSED to the operator
> when it happens.

**Hooks — disclosed for awareness, not gated:**

- One line per hook: event name and matcher summary, plus the settings
  file path (render `display_path` when present). Command text is NEVER in
  the artifact and never summarized here — the confidentiality contract
  extracts only event names and matcher strings. Apply the same zero-agent /
  capped-scan rules as skills (omit on a fully-scanned zero; anomaly-only
  section on a capped zero).
- Carry this line verbatim in substance: hooks execute in the operator's harness
  — they are surfaced here for awareness, not gated by Marshal. There is
  no approval mechanism for hooks; Marshal discloses what it
  found and stops there.

**Rules — consultative, never definitive:**

- One line per rule file: path (`display_path` when present), its
  `size_bytes`, and the artifact's `first_heading` when present,
  `(no heading)` otherwise — rule entries carry no description field and
  none is fabricated. Apply the same zero-agent /
  capped-scan rules as skills and hooks.
- List them as consultative conventions, never definitive — the same
  governance posture as skills and repo agents, but with no approval
  mechanism at all: rules are read as context, never invoked.

### Step 2 — Context-intake → `.marshal/context/brief.md`

Ingest the engagement's context sources into a structured brief. Sources include
docs, READMEs, ADRs, tickets, Slack history, meeting notes, or any artifact that
describes the intent, scope, and constraints of the engagement. Replace the
placeholder marker in `.marshal/context/brief.md` with the brief; preserve
existing real content on re-runs.

#### Step 2.1 — Gather intake sources

Accept any mix of connected and manual inputs. Manual-only operation must remain
useful when no connector is available. Common sources:

- **READMEs / docs:** read files in the repo root, `docs/`, `ADR/` directories.
- **Architecture decision records (ADRs):** capture decisions as constraints and
  open questions.
- **Tickets:** Jira / GitHub issues provided by the user (supply keys; do not
  autonomously search without direction).
- **Slack history:** channel or thread IDs provided by the user.
- **Meeting notes / digests:** local files in `context/meetings/` or user-pasted.
- **Design artifacts:** Figma file keys supplied by the user.

#### Step 2.2 — Classify each source

Before summarizing, classify each artifact:

- `source code` — repo files, config
- `runtime evidence` — test results, metrics, logs
- `business context` — PRDs, tickets, contracts, ADRs
- `communication` — Slack threads, email threads, meeting notes
- `ambiguous` — unclear; ask before filing

Do not silently treat `ambiguous` input as safe.

#### Step 2.3 — Extract signal and flag conflicts

For each source:
- Identify intent, scope items, constraints, key decisions, and open questions.
- Surface conflicting claims rather than resolving them automatically.
- When sources disagree, capture both claims, both sources, and one focused
  decision question for the operator.

#### Step 2.4 — Write `.marshal/context/brief.md`

Write the brief using this structure:

```markdown
## Engagement Brief

### Objective
<one sentence — what the engagement is trying to accomplish>

### In Scope
- <scope item 1>
- <scope item 2>

### Out of Scope
- <explicitly excluded item>

### Constraints
- <technical, legal, timeline, or budget constraint>

### Key Decisions
- <decision>: <outcome> (source: <where this was decided>)

### Open Questions
- <question that still needs an answer>

### Sources Consulted
- <source type>: <file path or ID>
```

Rules:
- Keep the brief under 60 lines. One line per fact.
- Do not restate the full engagement history — surface conflicts, missing info,
  and scope for operator review.
- Every "In Scope" bullet must be traceable to a source.
- Every "Open Question" must be answerable by a named person or process.

### Step 2.5 — MCP-connector setup (ticket + PR context)

Prompt the operator to wire up MCP connectors for Jira, Bitbucket, and GitHub
before proceeding. These connectors let the watcher and completion panel pull
live ticket and PR context directly — without them, the operator must supply
ticket text and links manually each time.

**Honest framing for the operator:**

> Marshal is repo-grounded first and connector-enriched optionally. The brief
> and repo map are built from the codebase and any context you paste in — MCP
> connectors are not required to proceed. Without a connector, supply ticket
> text and links manually during onboarding and during each watch cycle.
> With a connector, ticket + PR context flows into the handler automatically.

**Connectors to set up (prompt the operator for each):**

| Connector | What it provides |
|---|---|
| **Jira** MCP | Ticket descriptions, acceptance criteria, linked issues |
| **Bitbucket** MCP | PR diffs, review comments, CI status |
| **GitHub** MCP | PR diffs, issue body, workflow run status |

Detection heuristic:

- Ask the operator which trackers and VCS the engagement uses.
- If Jira: prompt to configure the Jira MCP connector (base URL, project key,
  authentication token). Do NOT auto-configure or read credentials from the
  environment — present the config template and let the operator fill it in.
- If Bitbucket: prompt to configure the Bitbucket MCP connector (workspace,
  repo slug, app password).
- If GitHub: the GitHub MCP connector ships with most Claude Code
  installations; confirm it is active and scoped to the engagement repo.

**Never auto-configure credentials.** Present the configuration template;
the operator supplies the values and activates the connector.

If the operator cannot or chooses not to set up a connector at this stage,
note the manual-supply path in `.marshal/context/brief.md` under
`### Sources Consulted` and proceed. Connector setup is not a blocking step —
it is an enrichment step.

### Step 3 — Access-doctor → surface the checklist

Run the access-doctor to check whether Marshal has the same access the engineer
has. Marshal cannot run CI, tests, or integrations without the access the
engineer uses day-to-day.

```bash
marshal onboard-status <engagement-root>
```

This command prints the current grounding status and the full access checklist:
VPN reachability, Docker availability, required env vars (DB DSN, API keys, etc.)
as declared in `.marshal/config.yaml`'s `access:` section.

Surface the checklist to the operator. For each missing item, the checklist
includes an actionable hint:

```
=== Marshal Access Check ===
Marshal needs the same access you have. Please grant any missing access before starting.

  [✗]  vpn
       → Cannot reach <host>. Marshal needs the same access you have — connect to the VPN first.
  [✗]  env:DB_DSN
       → DB_DSN is not set. Export your database DSN: export DB_DSN=<your-dsn>
  [✓]  docker

Summary: 1 present, 2 missing

Connect VPN / start docker / export the missing env vars,
then re-run `marshal onboard-status` to verify.
```

Encourage the operator to grant all missing access before proceeding. A missing
env var or unreachable VPN endpoint means Marshal cannot reproduce the engineer's
environment — implementation work will produce results the engineer cannot verify.

Re-run `marshal onboard-status` after granting access to confirm all checks pass.

### Step 4 — Verify grounding and report

After Steps 1–3, verify that the engagement is grounded:

```bash
marshal onboard-status <engagement-root>
```

The output must report `grounded: true`. If it does not:

1. Check whether `.marshal/context/repo-map.md` still contains the placeholder
   marker `<!-- MARSHAL: not yet grounded -->`. If so, Step 1 did not complete.
2. Check whether `.marshal/context/brief.md` still contains the placeholder
   marker. If so, Step 2 did not complete.
3. Fix the incomplete file and re-run `marshal onboard-status`.

Report to the operator:
- Whether the engagement is grounded (`context_present` result).
- Which files are populated and which are still placeholders.
- Any missing access items from the access-doctor.
- The next step (proceed to implementation, or grant missing access first).

**When invoked as the self-heal opener of `marshal go`** (an ungrounded
engagement — the common first-run path), the completion report is the operator's
handoff. After confirming `grounded: true`, tell them plainly:

> Onboarding done — I mapped the repos and wrote the dossier. Resume this
> engagement any time with `marshal go <name>`. Where do you want to start?

Then wait for direction (or, if a work item is already pending, proceed into it
under the normal work pipeline). Do not silently continue into implementation
without surfacing that onboarding finished.

### Step 5 — Knowledge-base build → `.marshal/knowledge/`

Actively build the engagement knowledge base during onboarding. The goal is
real domain facts extracted from the repo and tickets — not skeleton headers.
A skeleton is not a knowledge base; a skeleton that correctly traces one
business rule to a source is.

```bash
# ensure the directory exists (marshal onboard creates it; create if absent)
mkdir -p .marshal/knowledge
```

#### Step 5.1 — Extract gotchas from the repo

Read the codebase for evidence of pain points: TODO/FIXME/HACK comments,
duplicate workaround patterns, surprising environment requirements, test
helpers that paper over a known limitation. For each finding:

- State the fact concisely in `[GOTCHA:label]` format.
- Trace it to its source file and line range.
- Note when it was last touched (git blame the surrounding block).

Write to `.marshal/knowledge/gotchas.md`:

```markdown
# Gotchas — Cross-Cutting Tripwires

[GOTCHA:<label>] <Fact statement in one sentence.>
Source: `<file:line-range>` (last touched: <YYYY-MM>)
Why it matters: <one line on the blast radius if overlooked>
```

At least one gotcha per 1000 lines of non-test code is the minimum bar. If
no genuine gotcha is found, write a single entry stating why (e.g., "No
FIXME/HACK comments found; test suite coverage of edge cases is complete").
An empty or placeholder-only file is treated as ungrounded for knowledge
purposes.

#### Step 5.2 — Extract patterns from conventions and tickets

Identify the established ways of working: naming conventions, the dominant
data-access pattern, the error-handling convention, the migration pattern,
how the team scopes changes (per-ticket branch / trunk-based / feature-flag).
Cross-reference with any ticket text the operator provided.

Write to `.marshal/knowledge/patterns.md`:

```markdown
# Patterns — Established Ways of Working

[PATTERN:<label>] <Pattern statement.>
Source: `<file or ticket-ID>` — <one line on why this is the established path>
Deviation risk: <consequence of ignoring this pattern>
```

Rules for both knowledge files:

- Every entry MUST trace to a source (file path, line number, or ticket ID).
  A fact without a source is a belief, not a knowledge entry.
- Business rules are highest priority: rate-limit contracts, data-retention
  policies, access-control invariants, SLA commitments surfaced in ADRs or
  tickets. These belong in `patterns.md` under `[PATTERN:business-rule-*]`.
- Keep entries terse. One sentence per fact; one line per source; one line
  on deviation risk. Long prose goes in the brief, not the knowledge base.
- On re-runs (amendment or re-onboarding): preserve existing entries; append
  new ones with a `(updated: YYYY-MM)` annotation. Never silently overwrite.

#### Step 5.3 — Report the knowledge-base inventory

After building both files, report to the operator:

```
Knowledge base built:
  .marshal/knowledge/gotchas.md   — N entries (N sourced from codebase, N from tickets)
  .marshal/knowledge/patterns.md  — N entries (N conventions, N business rules)
```

If fewer than 3 total sourced entries exist across both files, surface a
warning: the knowledge base is thin and the watcher's accuracy may suffer.
Prompt the operator to supply additional tickets, ADRs, or meeting notes and
offer to re-run this step with the enriched input.

## Ground-Before-Acting Contract

> **This is the load-bearing invariant that protects every downstream Marshal
> operation.**

The discipline layer (`marshal_core.grounding`) enforces grounding at the
watch layer:

- `require_grounding(engagement_root)` raises `NotGroundedError` when
  `context_present` returns `False`.
- The watch handler (Step 0 of the handler prompt) calls `require_grounding`
  on each incoming message and refuses to ingest, classify, or act when the
  engagement is not grounded. The daemon advisory (`watch_poll.py`) also warns
  when `context_present` returns `False` at poll time.

Note: the completion panel (`marshal_core.completion`) and `marshal amend` do
**not** currently call `require_grounding` — grounding is not enforced at those
entry points (planned — not yet wired).

Do not attempt to work around the gate by setting `context_present` to `True`
artificially. The grounding check verifies real file content — not just file
presence. A file containing only the placeholder marker
`<!-- MARSHAL: not yet grounded -->` is treated as absent.

The remediation is always the same: run `marshal onboard` (scaffold), then run
this skill (populate), then confirm with `marshal onboard-status`.

## Outputs

| Output | Path | Notes |
|---|---|---|
| Repo map | `.marshal/context/repo-map.md` | Archetype, stack, entry points, key commands, structure, environment, read-first list. Replaces the scaffold placeholder. |
| Engagement brief | `.marshal/context/brief.md` | Objective, scope, out-of-scope, constraints, key decisions, open questions, sources. Replaces the scaffold placeholder. |
| Access checklist | (stdout from `marshal onboard-status`) | Printed to the operator; not written to disk. Describes missing VPN/docker/env-var access and how to fix each item. |
| Gotchas | `.marshal/knowledge/gotchas.md` | Sourced cross-cutting tripwires extracted from codebase and tickets. Each entry traces to a file + line range. |
| Patterns | `.marshal/knowledge/patterns.md` | Established conventions and business rules with source + deviation-risk annotations. |

After this skill completes, `context_present(engagement_root)` returns `True`
and every downstream Marshal skill can proceed without hitting the grounding gate.

## Next

- **Skill**: `attended-slack-watch` — once grounded, start or re-arm the watch daemon
  (`marshal watch <engagement-root> --mode monitor`, launched via the Monitor
  tool per the attended-slack-watch skill) to begin receiving and acting on client
  Slack messages. `--mode daemon` is a separate, unattended deployment that
  the CLI itself currently marks DORMANT pending soak-test — do not point an
  operator at it as the default next step.
- **Rich external sources** (Jira board, Confluence space, Drive spec, Figma
  files): re-run Step 2 with those sources as intake — supply keys/links and
  extend `brief.md` with the connector-backed evidence before starting watch.
- **Skip condition**: engagement is already grounded (`marshal onboard-status`
  reports `grounded: true` and the content is current). Proceed directly to the
  next planned phase without re-running this skill.
