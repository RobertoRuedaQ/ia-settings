---
name: rails-migrations
description: |
  Write and review Rails database migrations safely — reversible changes,
  lock-aware operations, staged rollouts, and out-of-band backfills. Patterns
  from 37signals (Fizzy). Use when adding or changing schema, indexes,
  constraints, or backfilling data on tables that may be large. Backfill jobs
  use Sidekiq, never inline migration loops.
  Do NOT use for: non-Rails projects, the Sidekiq/Redis job layer itself (no
  DB migrations — use background-job-designer), generated schema.rb edits, or
  greenfield modeling questions (use idiomatic-rails-patterns).
---

# Rails Migrations

Use for schema changes and migration safety. Assume production tables can hold millions of rows.

## Rules

- Make migrations reversible whenever possible (`reversible` blocks with explicit up/down SQL for data moves).
- Use raw SQL for data manipulation inside migrations; avoid referencing app models that drift over time.
- Avoid long table locks on large tables; split risky work into multiple deploy-safe steps.
- Separate schema changes from heavy data backfills.
- Prefer database operations that remain safe when rerun (`table_exists?` / `column_exists?` guards where migrations may run against varied states).
- Small inline backfills are fine in one migration (add column → `execute "UPDATE ..."` → tighten constraint); anything long-running moves out of the migration path entirely.
- On write-heavy tables, name `lock_timeout`/`statement_timeout` and use `disable_ddl_transaction!` for concurrent DDL.

## Script / Job Backfills (not everything is db:migrate)

Long-running or risky data backfills do NOT belong in the deploy migration window. Two acceptable homes:

- **Throttled Sidekiq job** (preferred for big tables): `in_batches`/`find_each` + a throttle (sleep or rate limit) between batches so you don't saturate the DB. Idempotent perform path so retries are safe. See background-job-designer for queue isolation, idempotency, and memory hygiene.
- **`script/migrations/*.rb`** run manually (e.g. via Kamal) for one-off operational backfills:
  - Document preconditions and run instructions in the header comment.
  - Preflight queries print scope before mutating.
  - Idempotent: skip rows already processed (`next if Entry.exists?(...)`) so reruns are safe.
  - Batched (`find_each` / `in_batches`), never one giant write.

## Safe Patterns

- Add nullable column -> backfill -> enforce `NOT NULL`.
- Canonical NOT NULL on a large table: add nullable column with a default for new rows → throttled Sidekiq backfill of existing rows → add a `NOT VALID` check constraint → `validate` it concurrently → optionally promote to `NOT NULL`.
- Add index concurrently when supported/needed (`algorithm: :concurrently`, `disable_ddl_transaction!`).
- Dedupe data (raw SQL delete of older duplicates) in the same migration immediately before adding a unique index.
- Data-only migrations are legitimate: `find_each` + `update!` up, `update_all` down — but only when the table is small; otherwise use a throttled job.
- Batched backfills instead of one giant write.

## Constraints: a deliberate choice, not a default

- Prefer DB-level uniqueness indexes over AR `validates uniqueness` (the validation races; the index doesn't).
- Foreign keys are a tradeoff: Fizzy deliberately removed all FKs (`foreign_key: false` on references) for DDL speed and shard-friendliness, keeping integrity in Rails. Either posture is fine — but make it consistent and documented, not accidental.
- Enforce odd invariants with cheap schema tricks where CHECK constraints are awkward: e.g. singleton tables via a `singleton_guard` column defaulting to 0 with a unique index.
- Atomic per-tenant counters: `account.increment!(:cards_count)` for sequence numbers + unique `[account_id, number]` index; a locked sequence row (`first_or_create!` under lock, `increment!`) for global ID sequences.

## Multi-Tenant Index Strategy

- When tenanting an app, replace global indexes with `[account_id, ...]` composites in a dedicated migration phase; drop now-redundant single-column indexes and comment why.
- Scoped uniqueness lives at the DB level: `add_index :tags, [:account_id, :title], unique: true`.

## Multi-Adapter Apps

- Supporting SQLite + MySQL/Postgres from one codebase: early-return adapter guards in migrations (`return if connection.adapter_name == "SQLite"`), adapter-specific DDL (FTS5 vs sharded fulltext), and dual schema dumps (`schema.rb` / `schema_sqlite.rb` via per-config `schema_dump`).
- SQLite in production: set `default_transaction_mode: immediate` to reduce `SQLITE_BUSY` under concurrent writers.
- Disable `dump_schema_after_migration` in production.
- The job layer is Sidekiq on Redis — there is no queue database to migrate or coordinate with schema changes.

## Staged Rollout Playbooks

- **Column replacement**
  - Deploy 1: add new nullable column.
  - Deploy 2: dual-write / backfill (throttled job).
  - Deploy 3: read from new column.
  - Deploy 4: enforce constraints, then drop old column later.

- **Constraint hardening**
  - Add data cleanup/backfill first.
  - Add index/constraint only after data is compliant.
  - Flip application behavior to rely on constraint once live.

- **Destructive changes**
  - First deprecate reads/writes in app code.
  - Remove usage in a separate deploy.
  - Drop columns/tables only after confirmation window.

## Red Flags

- Irreversible migrations without explicit reason.
- Combining schema rewrite + heavy data migration in one step.
- Large backfills inside transaction-heavy default migrations (move to a throttled Sidekiq job or `script/migrations/`).
- Inline `update_all`/loop backfills on million-row tables.
- Dropping columns/tables without staged deprecation.
- Referencing app models in migrations (model behavior drifts; use SQL or inline minimal AR classes).
- Adding a unique index without first deduping existing data.
- `validates uniqueness` with no backing unique index.
- Adding an index reflexively without classifying the query as core vs non-core.
