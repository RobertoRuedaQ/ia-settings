---
name: engagement-bootstrap
description: |
  The guided, one-time bootstrap a developer runs via ./marshal-bootstrap.sh. Walks
  them through OpenCode readiness, Slack-MCP wiring (as the user), learning their
  world into ~/.marshal/operator.yaml, and grounding a first engagement — ending
  with a working `marshal go`. Every step is idempotent/resumable.
---

# engagement-bootstrap

You are the installer. Drive the developer through setup conversationally, fixing
problems live. Every step below is **idempotent** — safe to re-run if anything fails.

## Step 1 — OpenCode readiness (hard gate)
Run `marshal doctor`. Guide install of `opencode`, the tool-less critic agent at
`~/.config/opencode/agent/critic.md`, and confirm `dual-harness.json`. Do NOT
proceed past a red OpenCode check.

## Step 2 — Slack MCP preflight (as the user)
The Slack connector is authenticated in Claude, out of band — this script cannot do
it. Preflight by calling the MCP `slack_read_user_profile` (no args → current user).
- On success: you now know the developer's identity. Ask for / confirm their **self-DM
  id** (where they'll chat with you).
- On failure: STOP this step and say exactly: "Connect the Slack connector in Claude,
  then re-run — `marshal go`/bootstrap is safe to re-run." Do not half-configure.
- If they decline Slack entirely: note it and continue (Slack features stay off).
- **If they choose `bot-token` mode** (a scoped Slack app instead of the as-you
  pair): before they create the app from `docs/slack-bot-manifest.yaml`, **remind
  them to personalize both identity fields** — replace the `<Your Name>` placeholder
  in `display_information.name` AND `bot_user.display_name` (e.g. `Ivan Iguaran
  Marshal`). Pasted unedited, every operator's bot lands on the same identity and
  you can't tell whose Marshal is whose in the workspace. Full flow:
  `docs/slack-transports.md`.

## Step 3 — Learn their world → operator.yaml
Walk their repos root(s); for each repo note archetype + which tracker/VCS it uses
(Jira/Bitbucket/GitHub/Slack). Write `~/.marshal/operator.yaml` (identity +
slack_self_dm, repos_root, tools, slack.transport: mcp). Re-running updates it.

## Step 3.5 — Forge credentials (so `marshal pr` works later)
Marshal opens/merges PRs and posts reviews **as the user**, against the forge(s)
just recorded in `tools.vcs`. Re-run `marshal doctor` and read the
`vcs-creds:<forge>` rows. For each one that is ⚠ (missing/malformed), **encourage
the developer to set it up now** and walk them through it using
`docs/credentials-setup.md`:
- **Bitbucket** → `~/.config/bb/config.toml` with a Bitbucket-scoped Atlassian
  `ATATT…` token (`bb auth login`). Token parsed with `tomllib`, never
  awk/sed/cut. Offer to run the verify snippet from the guide.
- **GitHub** → `gh auth login` (install `gh` first if absent).
Marshal **never stores the secret** — it only checks presence. This step is
encouragement, not a hard gate: if the developer isn't ready to open PRs yet,
note it and continue — but make clear `marshal pr` will fail until it's done.

## Step 4 — First engagement
Ask what they want to work on. `cd` there, run `marshal init` (it pre-fills
self_dm from operator.yaml), then ground it via the `repo-dossier-onboard` skill.
After grounding, run `marshal onboard` to confirm the engagement is ready.

## Step 5 — Finish
Print "you're all set" + the exact `marshal go <name>` command, and one line
summarizing what was configured (OpenCode ✓, Slack ✓/off, operator.yaml ✓, first
engagement grounded ✓).
