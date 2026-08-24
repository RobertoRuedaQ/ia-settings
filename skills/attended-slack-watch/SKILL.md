---
name: attended-slack-watch
description: |
  The attended Slack watch. A cheap background Python Monitor (`marshal watch
  --mode monitor`) polls the developer's Slack (via the user OR bot token) and
  PRINTS a trigger line per new message — zero model tokens while idle. The
  in-session agent handles each surfaced trigger per `slack_auth_mode`: as YOU via
  the Slack MCP (with the '— Authored by Marshal' footer) in user-token mode, or
  as the BOT via `marshal slack-send` (no footer) in bot-token mode — advancing an
  off-context watermark only after a successful reply.
---

# attended-slack-watch

The watch is two parts:

1. **A Monitor** — `marshal watch <root> --mode monitor`, a plain Python poller
   that READS Slack via the user token (`slack_token_env` + `slack_cookie_env`)
   every `poll_seconds` and **prints one line per new actionable message**:
   `SLACK[<role>] <ts> <user> [THREADREPLY(root=…)] <text> [files: N]`.
   **Launch it with the Claude Code `Monitor` tool (`persistent: true`), NOT a
   background Bash.** The Monitor tool streams each stdout line as an EVENT that
   wakes you while the poller **stays alive** — a background Bash would only wake
   you when it *exits*, so the poller would print but never reach you. The poller
   costs **zero model tokens** while idle and never posts, advances the
   watermark, or exits.
2. **You, the in-session agent** — you have the Slack MCP. Each Monitor event is
   a new message; you handle it **as the user** via MCP and record the watermark.
   The poller re-reads watch-state every cycle, so once you record, the message
   drops out of its window — **no relaunch needed; the Monitor keeps running.**

This replaces the old "the agent IS the poll loop" model (token-burning ~25-min
re-poll). The Monitor polls cheaply and streams events; you only spend tokens
when there's real work.

## Transports (set by `slack_auth_mode`)
Read `slack_auth_mode` from `.marshal/config.yaml` — it decides BOTH who Marshal
is and how you post. A background Monitor is available whenever ANY token is
configured (user OR bot) — it is NOT specific to the user pair.
- **`user-token`** (`slack_token_env` + `slack_cookie_env` = the `xoxc`/`xoxd`
  pair): the Monitor reads via the user token; you post **as you** via the Slack
  MCP, **with** the `— Authored by Marshal` footer.
- **`bot-token`** (`slack_token_env` = an `xoxb` bot token; no cookie): the
  Monitor reads via the bot token (it polls `conversations.history` just the
  same); you post **as the bot** via `marshal slack-send` — **NO footer** (the bot
  identity already discloses authorship; the footer is redundant, and the bot's
  own posts are filtered by `bot_id`, not the footer). **Never** post via the MCP
  `slack_send_message` here — that posts under YOUR name, defeating the bot.
- **No credentialed token** (MCP-as-you fallback): **no cheap background watch** (a
  Python process can't reach the agent-only MCP). Attended-live: handle messages
  while present, posting as you (with footer). Say so plainly — do not fake a
  background watch with a timed self-wakeup.

## Engagement routing (only when a channel is shared)
Several engagements can share ONE bot-DM. The poller for THIS engagement only
surfaces a message when it is tagged for this engagement **or untagged**:
- **Shared channel** (e.g. the bot-DM also watched by other engagements): the
  operator tags which Marshal a message is for —
  `@marshal - engagement: <name>` (e.g. `engagement: marshal`). A message tagged
  for a *different* engagement is skipped by this watch.
- **Single engagement / dedicated channel:** no tag needed — untagged messages are
  handled by default. The tag is purely a disambiguator; it is redundant when
  there's only one Marshal on the channel, so don't ask the operator for it there.

## Preconditions
- The engagement is grounded. If `marshal onboard-status` reports `grounded:
  false`, do NOT act — tell the developer to run onboarding (`require_grounding`).
- Your `slack_read_channel` / `slack_send_message` MCP tools work. If a call
  returns an auth error, see "Degraded state".

## Claim the watch
"claim the watch" →
1. Confirm grounding (`marshal onboard-status`).
2. **State the posting identity up front** (read `slack_auth_mode`): `bot-token` ⇒
   "replies post as the BOT — no footer"; `user-token`/MCP-as-you ⇒ "replies post
   as YOU, with the `— Authored by Marshal` footer". Say which BEFORE handling the
   first message — the client sees this identity, so it must never be a surprise.
3. Baseline the watermark to the newest existing message so the stale backlog
   isn't replayed (`marshal watch-state show` to see current; record the newest
   ts if starting fresh).
4. Launch the poller with the **`Monitor` tool** — NOT a background Bash:
   `Monitor(command="marshal watch <root> --mode monitor", description="<eng>
   Slack watch (self-DM + client channels)", persistent=true)`. Each new message
   then arrives as a **Monitor event** (a notification in chat) while the poller
   stays alive. Stop it later with `TaskStop` (see "Release").
   - If the user token isn't configured, skip the Monitor and run attended-live
     (handle messages via MCP when the developer points you at them); tell them
     the background watch needs the `xoxc`/`xoxd` pair (see docs/slack-transports).

## Handle each surfaced trigger (on a Monitor event, or a direct DM)
When a **Monitor event** arrives (the poller printed a `SLACK[...]` trigger), or
the developer DMs you directly, handle oldest-first:

1. **Resume point.** `marshal watch-state show` → note `channel`, `last_seen_ts`,
   and the `handled` ts list (dedup floor). Skip any ts already in `handled`.
2. **Read full context** via MCP `slack_read_channel` / `slack_read_thread` for
   the trigger's channel + ts (the trigger line is a pointer, not the full text).
   **Files** (`files: N`) — the MCP cannot fetch file bytes; use the user-token
   path. Each file object on the message has an `id` (e.g. `F0123ABCD`):
   - **download** (pass the file ID directly — no need to dig out url_private):
     `marshal slack-file download <file-id> --out <scratchpad>/<filename>`
   - **send a file**:
     `marshal slack-file upload <channel> <path> [--comment "…"] [--thread <ts>]`
3. **Per message:**
   a. Confirm grounding (`marshal onboard-status`); if not grounded, reply asking
      the developer to onboard and stop.
   b. Do the work / answer plainly. Surface held items, drafts, status, decisions.
   c. To post to a **client** channel, first run `marshal post-check --channel
      <id> --text "<draft>"`. If it prints `held: ...`, do NOT post — HOLD it for
      the developer's approval in the self-DM. Post only once they approve.
   d. **Post per the auth mode (`slack_auth_mode`) — this decides identity + footer:**
      - **`bot-token`** → post with `marshal slack-send --autonomous --channel
        <id> --text "<draft>" [--thread <ts>]`. This sends **as the bot**; it
        adds NO footer (the bot identity is the disclosure) and applies your
        `--tag`/config recipients. **Always pass `--autonomous` from the watch
        loop** — the flag declares the send as autonomous on the `post_outcome`
        audit event (attended operator sends omit it; the verb cannot observe
        its caller). Do NOT use MCP `slack_send_message` — that posts as YOU.
      - **`user-token` / MCP-as-you** → pass your draft through `marshal post-format
        --text "<draft>"` (appends the `— Authored by Marshal` footer) and post its
        output via MCP `slack_send_message`. Posting under the developer's identity
        is indistinguishable from one they typed, so the footer discloses agent
        authorship.
   d-bis. **Retracting a post you should not have sent.** If a bot post was
      mistaken or is superseded, retract it with `marshal slack-delete --channel
      <id> --ts <ts>` — the sanctioned undo. It is bot-token only and own-post
      only, and it records a `slack_retracted` event so the retraction is
      auditable. Do NOT reach for a raw `chat.delete` call (the watch-guard
      tripwire denies it, and a deletion with no record is worse than the post).
      Deletion is irreversible and visible: disclose the retraction to the
      operator, including that the message was briefly visible.
   e. **Reply IN THE THREAD — always (the discipline anita proves out).** A
      thread IS the conversation/item, keyed by its `thread_root` ts. Post in-thread
      (bot: `marshal slack-send --autonomous … --thread <thread_root>`; as-you: MCP
      `slack_send_message` with **`thread_ts = <thread_root>`**):
      - trigger was a thread reply (`THREADREPLY(root=<ts>)` on the trigger line)
        → `thread_ts` = that root;
      - trigger was a top-level message → `thread_ts` = that message's OWN ts
        (your reply STARTS its thread).
      NEVER reply top-level to a threaded item — with two conversations going at
      once, a top-level reply collapses them into the channel (the exact pain the
      anita posture avoids). Every post for an item goes in that item's thread.
      **Per-thread continuity:** same `thread_root` → same working context — your
      session already remembers the thread; keep per-thread notes so a later reply
      resumes where it left off.
      **Then durably track the root** so a reply is caught even after the parent
      ages out of the history window:
      `marshal watch-state track-thread --channel <ch> --root <thread_root>`;
      untrack on resolution: `marshal watch-state untrack-thread --channel <ch>
      --root <thread_root>` (keeps the set bounded). Without the track, a reply on
      a thread whose parent scrolled past the window is missed (the deafness bug).
   f. Record a ledger entry for the item.
   g. **Advance the watermark only after a successful reply** —
      `marshal watch-state record --channel <ch> --ts <message-ts>`. If the reply
      failed, do NOT record — the message is retried next launch (delay, never drop).
      **Durability:** advance-on-success is at-least-once-attempted — we **never
      drop** a message. If a reply posts but the state-write then fails, the
      message may be re-handled once (a duplicate reply). Acceptable: never-drop
      outranks never-dup.

The Monitor **keeps running** — no relaunch. The poller re-reads watch-state each
cycle, so once you `record`, that message drops out of its window and the next
event is the next genuinely-new message. The watermark + handled set live in
`.marshal/watch-state.json` (off-context), so a compaction or session restart
reclaims the watch without re-handling old messages. The poller never advances
the watermark itself, so even if the Monitor is stopped, a re-claim re-detects
anything unhandled (never a drop).

## Release the watch
"release the watch" → **first** run the release verb, **then** stop the Monitor:

1. `marshal watch-release` — records the `watch_release` event and prints the
   rule-13 session-end harvest moment ("did you learn anything this session
   that only exists in your head?"). Answer it honestly: if yes, run the
   printed `marshal knowledge add` before moving on. The verb prints a nudge
   only — nothing is auto-written.
2. Stop the Monitor with **`TaskStop`** (the persistent Monitor runs until the
   session ends or you stop it).

Attended-only: when this session ends the Monitor ends — that's expected; a
re-claim resumes from the recorded watermark with no drop. (An unexpected
session end skips the harvest moment — that's acceptable; the next `marshal pr`
or `cpd-conclude` nudge catches accumulated learnings.)

## Degraded state (auth/MCP failure)
If `slack_read_channel` / `slack_send_message` returns an auth/expiry/rate error:
do NOT advance the watermark, surface a LOUD notice to the developer (terminal,
and the self-DM if posting still works), and wait for them to reconnect the Slack
connector — then resume from the last recorded `ts`. If the **Monitor** logs a
token/cookie auth failure (the `xoxc`/`xoxd` pair rotated), tell the developer to
re-grab the pair from the browser and restart the watch. The watch must never
appear alive-but-inert; a stalled watermark + a visible error is the contract.

## Hard rules
- **Posting identity + footer follow `slack_auth_mode`:**
  - `bot-token` → post as the BOT via `marshal slack-send`; **no footer** (the bot
    identity discloses authorship; own posts are filtered by `bot_id`). NEVER post
    via the MCP on a bot-token engagement — it sends under your name and defeats
    the whole point of the bot.
  - `user-token` / MCP-as-you → post as YOU via the MCP, **with** the `— Authored
    by Marshal` footer (`marshal post-format`). Who-sends-it (you) and
    disclosing-an-agent-wrote-it (the footer) are both true at once.
  The **poller READS** via whichever token is configured (user OR bot) — reading is
  cheap and identical; only the posting identity differs by mode.
- Client-channel content always passes `marshal post-check`; delivery / incident /
  exec / irreversible claims are HELD for approval.
- One item per surfaced message; oldest-first; advance-on-success only.
- The unattended `daemon` mode (a headless one-shot handler per message, posting
  via the token) is a separate deployment, not this attended skill.
