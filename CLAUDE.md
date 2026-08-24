## Working discipline

A few habits that make changes to unfamiliar code safer and more honest,
regardless of stack. Destructive commands and edits to sensitive files
already have a mechanical safety net in `settings.json`'s permission
deny-list (`rm -rf`, force-push, `git reset --hard`, `DROP TABLE`, edits to
credentials/`.env`/`schema.rb`/`Gemfile`/initializers) — the items below are
the judgment calls a deny-list can't enumerate.

### Ground before acting
Before editing a codebase you don't already know well, read enough of it —
structure, the relevant modules, existing conventions — to act with real
understanding. A confident-looking edit built on a guess is worse than a
slower, correct one.

### Search broadly via subagents
For anything that spans 2+ directories, 2+ naming conventions, or would
otherwise take reading 3+ files to answer ("where is X used", "how is Y
wired") — delegate to the `Explore` (or `general-purpose`) subagent instead
of a single grep that might miss results, or a guess.

### Verify before claiming
Never say "done", "works", or "passing" without checking the current state:
re-read the file as it stands now, re-run the test or command. "It should
work" is not verification, and neither is "I checked earlier" if anything
has changed since.

### Deploys and infrastructure are halt-and-ask
Never deploy, restart a service, run a migration against a shared or
production datastore, or change infrastructure on your own initiative.
Before proposing such an action, state the target environment, the exact
commands, the expected impact, and the rollback plan — then wait for an
explicit go-ahead. One approval never carries over to the next action.

### Don't touch what you didn't create, without asking
Deleting, overwriting, moving, or renaming a file you didn't create needs
explicit authorization — even when it isn't covered by the deny-list.

## Knowledge writeback

When a debugging session ends in a surprise, or a design decision gets
confirmed as the right way to work, write it into the project's persistent
memory before moving on — don't let it die in this session's scratch/chat
context.

Two shapes are worth distinguishing in the memory body, even though the
frontmatter only defines `user`/`feedback`/`project`/`reference`:
- **Gotcha** — a one-off technical trap (e.g. "a pipe without `pipefail`
  hides the real exit code behind `tail`'s").
- **Pattern** — a confirmed, repeatable way of working for this project.
Prefixing the fact with **Gotcha:** or **Pattern:** keeps it searchable
without needing a new frontmatter field.

**Test:** "if this session ended right now, would the next session on this
project need to know this?" If yes, write it now — "later" is when it gets
forgotten.

**Keep it current:** a memory isn't append-only. When the underlying fact
changes, or a gotcha gets fixed, update or delete the memory in the same
sitting — a stale memory that contradicts the current code is worse than no
memory at all. On a genuine conflict between what a memory says and what
the code does, the code wins, unless the memory records a product/business
decision the code can't express on its own.

## A project's own documentation/learnings conventions are part of done

Some projects define their own documentation structure beyond this file —
e.g. a dual set of docs (one for the engineering team, one written in plain
language for non-technical stakeholders) kept next to the code, or a
project-local learnings log that captures gotchas and confirmed decisions as
they happen. When a project defines either of these, treat updating them as
part of a task's definition of done — the same task that changes the
behavior updates the doc/log that describes it, not a follow-up step that
may or may not happen later. Check the project's own `CLAUDE.md` (if it has
one) for the specifics of what it expects and where.

## Long docs get a compact sibling

Any doc that grows past ~100 lines and gets read for context on a regular
basis — a plan's `spec.md`, a long README, an architecture note — should get
a `.compact.md` sibling: a 25-35% summary covering the same ground. Prefer
the compact form when you just need orientation; read the full doc when you
need the detail. Keep the pair in sync — an edit to the full doc that isn't
reflected in its compact sibling is a doc going stale, same as any other.

## Security & data-privacy baseline

Applies to every project, not just this one — treat it as a floor, not a
suggestion, and raise the bar further when the project itself demands more
(regulated data, a compliance framework, a client contract).

- **No known-shape secrets in source, ever.** Tokens, API keys, passwords,
  and connection strings come from environment variables or a secrets
  manager — never a literal in code, a config file committed to the repo,
  or a log line. If a secret was ever committed, treat it as compromised:
  rotate it, don't just delete the line. The mechanical hook below catches
  *known secret shapes* (AWS, GitHub, Slack, Stripe, PEM, JWT, and a
  generic `key = "literal"` pattern) — it is not a guarantee against every
  possible secret format, and it is blind to anything that doesn't go
  through the Bash tool (an MCP server call that publishes/deploys
  directly) or that uses shell indirection to avoid the literal command
  string (`$GIT commit`, an `eval`'d string). Don't treat "the hook didn't
  block it" as proof a diff is clean.
- **`.gitignore` is verified, not assumed, at project start.** Before the
  first commit of a new project, confirm it excludes `.env*`, `*.key`,
  `*.pem`, `*credentials*`, `*.tfstate`, cloud credential files
  (`.aws/credentials*`, `*.p12`, service-account JSON), and any sensitive
  data export specific to the domain (account statements, ledgers, anything
  with account numbers or PII). An outdated or missing `.gitignore` is a
  blocking finding, not a nice-to-have fix.
- **Financial and PII-handling projects get governance built in, not
  bolted on.** Any project that touches money, bank/ledger reconciliation,
  or personal data MUST invoke `ai-governance-audit` and
  `bank-reconciliation-patterns` (where applicable) as part of
  definition-of-done — same enforcement weight as `durable-plan` for large
  work. A privacy/data-handling note (what's collected, where it's stored,
  who can see it, how long it's kept) is part of that project's
  deliverable, not an afterthought.
- **A leak is a halt-and-ask event.** Discovering a secret or sensitive
  file already committed/pushed is not something to quietly fix and move
  on from — flag it to the user immediately per the halt-and-ask discipline
  above, because a rotation or history rewrite may be needed and that's
  their call.

## Tools that back this discipline

These make the habits above mechanical instead of aspirational — invoke
them, don't just remember they exist:

- **`skeptic` agent** — invoke it on load-bearing claims before treating
  them as settled: a root-cause diagnosis, "this is safe/done/fixed," a
  design decision made without dissent. This is the mechanical form of
  *verify before claiming* above — it exists to argue with you before
  reality does.
- **`durable-plan` skill** — invoke it before starting work that touches
  3+ files or carries real acceptance criteria. Write the spec and task
  plan to disk first. This is the mechanical form of *ground before acting*
  for anything too big to hold in one sitting. Once a plan exists at
  `docs/plans/<slug>/plan.md`, the statusline and session-start hooks pick
  its progress up on their own — no need to re-announce where things stand.
- **`memory-harvest` skill** — invoke it periodically, or right after a
  session that produced several memory writes, to promote what's durable
  into committed docs and prune what's stale. This is the mechanical form
  of the *knowledge writeback* section above.
- **`hooks/secret-scan.sh` (PreToolUse hook)** — wired globally in
  `settings.json`, so it runs for every project, not just this one. It
  inspects any `git commit`/`git add ... commit`/`git push`-shaped Bash
  invocation and mechanically blocks it (exit code 2 — the call never
  executes) when it finds a known-shape secret literal or a sensitive
  filename in what's actually about to be committed/pushed. This is the
  mechanical form of *no known-shape secrets in source* above. See
  `docs/plans/security-data-privacy-baseline/spec.md` for exactly what it
  does and does not catch.
- **`project-security-bootstrap` skill** — invoke it at the start of any
  new project to verify `.gitignore` coverage, scan the project's current
  state for anything already leaked (using the same pattern set as the
  hook above), and — for financial/PII-handling projects — hard-require
  the governance skills before implementation proceeds. This is the
  mechanical form of *`.gitignore` is verified, not assumed*.
