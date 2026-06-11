---
name: background-job-designer
description: |
  Design, review, or fix Sidekiq + Redis background jobs in Ruby on Rails.
  Use when a job needs to be created, a slow process should move async, a job
  is leaking memory, causing race conditions, hammering the database, or
  behaving unpredictably under load. Prioritizes: race-condition prevention,
  zero memory leaks, minimal resource usage, Redis as the coordination
  backbone.
  Do NOT use for: Solid Queue / GoodJob / Delayed Job projects (patterns
  differ — fall back to Rails defaults), one-off scripts, ActiveJob without a
  real backend, or scheduling questions (use the `schedule` skill).
---

# Background Job Designer

Design and review background jobs that are safe, lean, and production-proof.
Every job recommendation assumes Sidekiq + Redis, millions of records,
and a live system where a bad job can take down the entire worker pool.

---

## Entry Point — Classify Before Designing

Before writing a single line of code, answer these four questions.
If the answers are unknown, ask the user explicitly.

**1. What triggers this job?**
- User action (synchronous trigger → latency matters)
- Another job (pipeline/chain → failure propagation risk)
- Scheduler/cron (recurring → overlap risk)
- Webhook / external event (at-least-once delivery → idempotency mandatory)

**2. What is the data scope?**
- Single record → simple job
- Collection of records → batch strategy required (find_each, not all)
- Cross-tenant or global scan → partition strategy required

**3. What external systems does it touch?**
- Database writes → locking and transaction scope
- External APIs → rate limits, timeouts, circuit breaker
- Redis directly → key naming, TTL, atomicity
- File system or object storage → cleanup strategy

**4. What is the failure mode?**
- Can it safely retry? → idempotency check
- Does partial completion leave dirty state? → rollback or compensation strategy
- Does it hold locks across retries? → deadlock risk

---

## Reference Files — Read the One That Matches the Task

- `references/race-conditions-and-memory.md` — Distributed locking with Redis
  (Lua atomicity, ownership, ensure-release), optimistic locking,
  `sidekiq-unique-jobs` strategies, and the five memory-leak rules
  (no class state, stream large datasets, release AR connections, IDs not
  objects in args, avoid closures)
- `references/redis-performance-idempotency.md` — Redis counters/rate-limits/
  dedupe, queue strategy by resource profile, orchestrator + per-record job
  split, query rules inside jobs, retry config, and the idempotency checklist

---

## Core Rules — Always Apply

1. **Idempotency first.** Every job must be safe to retry. At-least-once delivery
   is the default — design for it or it bites you.
2. **IDs in args, never objects.** Sidekiq serializes args to Redis; large args
   = Redis pressure + slow enqueue.
3. **`find_each`, never `.all.each`.** And `select` only what the job needs.
4. **Lock with Redis (Lua check-and-release), not advisory DB locks.** Advisory
   locks don't release on worker crash.
5. **Always release locks in `ensure`.** Never assume happy path.
6. **Match queue to resource profile, not job name.** `critical` for user-
   blocking, `default` for normal async, `bulk` for >1000 records.
7. **Orchestrator + per-record job split** for batches. One job per record is
   parallelizable, retryable, and recoverable.
8. **No closures, no `@@class_vars`, no `@instance_vars` carried across jobs.**
   Workers are reused — state leaks.
9. **No external HTTP inside a DB transaction.** Keep transactions short.
10. **Rescue specific retriable errors, not `StandardError`.** Generic rescues
    hide bugs.

---

## Anti-Patterns — Never Do

- `User.all.each` inside any job — always find_each
- `sleep N` for rate limiting — use Redis counter + re-enqueue
- Instance variables (`@var`) shared across job invocations — jobs are not stateful
- Class variables (`@@var`) for cross-job state — use Redis
- Calling external HTTP inside a DB transaction
- Raising generic `StandardError` to trigger retry — use specific retriable errors
- Rescue and swallow exceptions silently — always log with structured context
- Jobs that enqueue themselves recursively without a termination condition
- Storing ActiveRecord objects in job args — IDs only
- Using `Kernel#sleep` instead of `wait:` on re-enqueue

---

## Output — Job Design Report

When designing or reviewing a job, always produce this structured output:

```
JOB: <ClassName>
Queue: <queue_name> — reason: <why this queue>
Trigger: <what enqueues this job>
Data scope: <single record / batch N records / global scan>
Estimated duration: <ms / seconds / minutes>
Retry strategy: <count + backoff reasoning>

Race condition risks identified:
  - <risk>: mitigated by <strategy>

Memory risks identified:
  - <risk>: mitigated by <strategy>

Redis usage:
  - <key pattern> → <purpose> → TTL: <value>

DB query profile:
  - <query description> — SELECT columns: <list> — uses index: <yes/no/unknown>

Recommended implementation: <option A / B / C with one-line rationale>

DHH Verdict: <one sentence, the final call>
```
