---
name: rails-webhooks
description: |
  Build and review Rails webhook systems with safe delivery, retries,
  observability, and tenant-aware security, modeled on 37signals' Fizzy
  event-driven pipeline. Use when adding or reviewing outbound webhook
  delivery, inbound webhook receivers, retry/circuit-breaker logic, or webhook
  admin tooling. Delivery runs on Sidekiq workers; tests are RSpec.
  Do NOT use for: non-Rails projects, simple synchronous third-party API calls
  with no delivery/audit requirements, or the generic job mechanics (use
  background-job-designer); for SSRF/URL validation detail see
  rails-security-multitenancy.
---

# Rails Webhooks

Use for outbound/inbound webhook architecture and reliability. Modeled on Fizzy's event-driven webhook pipeline (with Campfire's simpler bot webhooks as contrast).

## Delivery Model (outbox pattern)

- Domain events enqueue one dispatch worker; the dispatch worker fans out, creating one persisted `Delivery` row per webhook, each with a state enum (`pending in_progress completed errored` — string-backed via `index_by(&:itself)`).
- Each delivery row auto-enqueues its own send via `after_create_commit { DeliveryWorker.perform_async(id) }` — persist first, deliver second, so state survives crashes and retries.
- Make fan-out resumable: persist a cursor (last-processed webhook id) and have the dispatch worker `find_each(start: cursor)` updating the cursor as it goes; if it needs to yield, re-enqueue itself to continue from the cursor so a mid-batch crash resumes rather than restarts. (Sidekiq Pro batches are an alternative if available.)
- Record request metadata (headers, payload) and response (status, body) on the delivery row for audit/debugging. Cap stored/streamed response bodies (~100KB) with a running byte count.
- Use a dedicated Sidekiq queue (`sidekiq_options queue: :webhooks`) so slow destinations can't starve other work. See background-job-designer for queue isolation and idempotency.

## Failure Classification (the key distinction)

- **Expected destination failures** (timeout, TLS, DNS, connection refused, HTTP 4xx/5xx): rescue, mark delivery `completed` with a symbolic error (`response: { error: :connection_timeout }`), and **return normally — do NOT re-raise**. The delivery ran; the destination failed. Sidekiq must not retry it.
- **Unexpected exceptions** (our bug): mark `errored!`, then **re-raise** so Sidekiq's retry machinery (`sidekiq_options retry: N`) takes over.
- This split keeps retry behavior, dashboards, and delinquency tracking honest. Never let a dead destination consume Sidekiq's retry budget meant for real code errors.

## Delinquency Circuit Breaker

- Track consecutive failures + `first_failure_at` per webhook; auto-deactivate after N failures spanning a minimum window (Fizzy: 10 failures over 1+ hour).
- Reset the counter on success.
- Surface inactive state in the UI with a manual reactivation endpoint (`resource :activation`).

## Security Baseline

- Treat webhook URLs as untrusted input; apply full SSRF protections (resolve + validate IP, block private ranges, pin IP, re-validate per redirect — see rails-security-multitenancy).
- Revalidate destination at send time, not just on create.
- **Destination URL is immutable after create** — updates permit name/subscriptions only. Retargeting requires a new webhook (and new secret).
- Sign payloads: HMAC signature header + timestamp header.
- Whitelist subscribable events at the model layer: `normalizes :subscribed_actions, with: ->(v) { Array.wrap(v).map(&:to_s).uniq & PERMITTED_ACTIONS }`.
- Require admin-level auth for webhook management endpoints.

## Integration Adapters

- One delivery pipeline can serve multiple destination types: detect by URL pattern (`for_slack?`, `for_campfire?`), then vary content type, payload format (JSON/form/HTML), and rendering template per destination. Don't fork the delivery code per integration.
- Render payload URLs with tenant-correct `script_name` so links in payloads work.

## Inbound Webhooks (receiving)

- Verify the signature first (`construct_event`-style), then re-fetch canonical state from the provider's API instead of trusting payload content or ordering.
- Keep the controller action thin: verify, enqueue a Sidekiq worker, return 2xx fast. Do the real work async and idempotently (dedupe on the provider's event id).
- For chat-bot style callbacks: gate what responses can do by content type (only `text/plain`/`text/html` become replies), and prevent loops — never trigger a bot from its own messages.

## Tenant Safety

- Keep webhook records and delivery queries tenant-scoped.
- Ensure event fan-out cannot leak cross-tenant data.

## Operational Hygiene

- Recurring cleanup of old delivery records by retention policy (e.g. every 4 hours, `delete_all` on a stale scope) via a scheduled Sidekiq job.
- Surface delivery status/history in the webhook admin UI.
- Emit useful logs/metrics for success rate, retries, and latency.

## Testing (RSpec)

- Worker specs: stub the destination with WebMock; assert `completed` + symbolic error on timeout/4xx/5xx and that the worker does NOT raise; assert `errored!` + re-raise on an unexpected exception.
- Retry semantics: assert expected destination failures don't schedule a Sidekiq retry, while code errors do.
- Circuit breaker: drive N consecutive failures and assert auto-deactivation + counter reset on success.
- Inbound: assert invalid signatures are rejected before any work is enqueued; assert duplicate event ids are deduped.
- Always stub external HTTP — never hit a real destination.

## Red Flags

- Fire-and-forget delivery with no persisted audit trail.
- Retrying destination failures the same way as code errors (re-raising a timeout into Sidekiq's retry queue).
- Mutable webhook destination URLs.
- No circuit breaker — hammering dead endpoints forever.
- Unbounded reads of destination responses.
- No tenant scoping in delivery creation/lookup.
- No backpressure or queue isolation for high-volume events.
- Inbound receivers doing heavy work synchronously in the controller.
