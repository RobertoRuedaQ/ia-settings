---
name: rails-init
description: |
  Structured onboarding for Ruby on Rails projects. Use when starting work on
  a Rails codebase, running /init on a Rails project, or when the user asks
  to "understand the project", "analyze the codebase", or "get context" on a
  Rails app. Reads Gemfile → schema.rb → routes.rb → initializers → frontend
  → test suite → app/ subdirs in that order and writes
  .claude/PROJECT_REPORT.md.
  Use this instead of the generic `/init` whenever a Gemfile or Rails directory
  structure is present.
  Do NOT use for: non-Rails repos (no Gemfile, no `config/application.rb`),
  Ruby gems/libraries without a Rails app, or follow-up exploration after
  PROJECT_REPORT.md has already been written and is current.
---

# Rails Project Onboarding Skill

Efficient, structured onboarding for Ruby on Rails codebases. Reads the
minimum set of files that reveal the most about the project — following Rails
conventions rather than exploring blindly.

## Entry Point — Check Report First

Before reading anything else, check if `.claude/PROJECT_REPORT.md` exists.

**If it exists:** read it, report to the user that the project report was found
and summarize its last_updated date and key sections. Then check if any of these
conditions apply — if so, refresh the relevant sections:

- `db/schema.rb` modified after `last_updated`
- `Gemfile` modified after `last_updated`
- `config/routes.rb` modified after `last_updated`
- User explicitly asks to refresh or re-analyze

**If it does not exist:** run all phases below and write the report at the end.
Inform the user: "No project report found. Running full analysis and writing
.claude/PROJECT_REPORT.md for future sessions."

---

## Reading Order

Work through these phases in sequence. Each phase answers a specific question.
Do not explore `node_modules/`, `.git/`, `tmp/`, `log/`, or `public/assets/`.

---

### Phase 1 — Gemfile: What does this app depend on?

Read `Gemfile` (not `Gemfile.lock`). Extract:

**Runtime behavior gems** — flag anything that changes default Rails behavior:
- Auth: `devise`, `authlogic`, `clearance`, `rodauth`, `pundit`, `cancancan`
- Soft deletes: `paranoia`, `discard`, `acts_as_paranoid`
- Multitenancy: `acts_as_tenant`, `apartment`, `marginalia`
- Background jobs: `sidekiq`, `delayed_job`, `good_job`, `resque`
- Money/currency: `money-rails`, `monetize`
- State machines: `aasm`, `statesman`, `workflow`
- File storage: `carrierwave`, `shrine`, `active_storage` (built-in)
- Search: `searchkick`, `pg_search`, `ransack`, `elasticsearch-model`
- Pagination: `kaminari`, `pagy`, `will_paginate`
- API serialization: `active_model_serializers`, `jsonapi-serializer`, `blueprinter`, `alba`
- Multi-db / sharding: `octopus`, `makara`

**Frontend strategy gems** (also covered in Phase 5):
- `turbo-rails`, `stimulus-rails` → Hotwire stack
- `react-rails`, `react_on_rails` → React integration
- `webpacker` → legacy Webpack (Rails 5/6 era)
- `importmap-rails` → importmap (Rails 7+ default)
- `jsbundling-rails` + (`esbuild`, `rollup`, `webpack`) → JS bundling
- `cssbundling-rails` → CSS bundling
- `sprockets` → legacy asset pipeline

**Rails version** — note it explicitly; behavior differs across 5.x / 6.x / 7.x / 8.x.

---

### Phase 2 — Schema: What is the domain model?

Read `db/schema.rb` (or `db/structure.sql` if schema.rb is absent).

Identify:
- **Core tables**: ignore `schema_migrations`, `ar_internal_metadata`, `active_storage_*`, `action_*`
- **Soft delete pattern**: tables with `deleted_at` column
- **Multi-tenancy signals**: `tenant_id`, `account_id`, `organization_id` on most tables
- **Enum columns**: integer columns named with known patterns (`status`, `state`, `role`, `kind`)
- **Polymorphic associations**: `*_type` + `*_id` column pairs
- **STI**: tables with a `type` string column
- **Key relationships**: sketch the main foreign key graph — which tables are central hubs
- **Index coverage**: note tables with sparse or no indexes — relevant for future performance work

---

### Phase 3 — Routes: What does the app expose?

Read `config/routes.rb`.

Determine:
- **API-only or hybrid**: presence of `namespace :api` or `defaults format: :json`
- **Versioning**: `namespace :v1`, `namespace :v2`
- **Admin area**: `namespace :admin`, `mount RailsAdmin`, `mount ActiveAdmin`
- **Mounted engines**: Sidekiq web UI, Flipper, LetterOpener, etc.
- **Notable nested resources**: deep nesting signals complex authorization
- **Non-REST routes**: custom `collection` or `member` actions reveal domain actions

---

### Phase 4 — Initializers: What is configured at boot?

Scan `config/initializers/`. Read each `.rb` file title and its first few lines.
Flag any that configure:
- Third-party service clients (Stripe, Twilio, SendGrid, AWS SDK, etc.)
- Feature flags (`flipper`, `rollout`, `split`)
- Error monitoring (`sentry`, `honeybadger`, `bugsnag`, `rollbar`, `appsignal`)
- ORM extensions (`paper_trail`, `audited`, `acts_as_taggable_on`)
- Authorization setup (Pundit policy defaults, CanCan ability loading)
- CORS (`rack-cors` config)
- Background job configuration (Sidekiq queues, concurrency)
- Custom inflections or locale defaults

Also read `config/application.rb` for:
- Autoload paths
- Middleware stack customizations
- Time zone and locale
- Custom generators

---

### Phase 5 — Frontend Strategy: How does the UI work?

**Step 5a — Check for API-only mode**
```ruby
# config/application.rb
class Application < Rails::Application::API  # → pure API, no view layer
```

**Step 5b — Check asset/JS pipeline**

| File present | Implies |
|---|---|
| `config/importmap.rb` | Importmap (Rails 7+ default, no Node build step) |
| `config/webpack.config.js` or `webpacker.yml` | Webpacker (legacy, Rails 5/6) |
| `package.json` with `esbuild`/`rollup`/`vite` | jsbundling-rails |
| `vite.config.ts` or `vite.config.js` | Vite + `vite_ruby` gem |

**Step 5c — Check for Hotwire**
Look for `app/javascript/controllers/` and `.html.erb` files using
`turbo_frame_tag` or `turbo_stream`.

**Step 5d — Check for React or Vue**
- `app/javascript/components/` or `app/javascript/packs/`
- `*.jsx`, `*.tsx`, `*.vue` files in `app/javascript/`

**Step 5e — Check for dedicated frontend**
Top-level `frontend/`, `client/`, or `web/` directory with its own `package.json`.

**Summarize** as one of:
- **Server-rendered** (ERB + Sprockets or Importmap, minimal JS)
- **Hotwire** (Turbo + Stimulus, Rails 7+ style)
- **Hybrid Hotwire + React** (Turbo frames + React islands)
- **API + decoupled SPA** (Rails API, separate React/Vue/Angular app)
- **Legacy Webpacker** (Rails 5/6, mixed jQuery/React/Vue via Webpacker)

---

### Phase 6 — Test Suite: How is quality verified?

Check which framework is in use (`spec/` → RSpec, `test/` → Minitest).

**RSpec:** read `spec/rails_helper.rb`, check for `spec/support/`, `spec/factories/`,
`spec/system/`.

**Minitest:** read `test/test_helper.rb`, check for `test/system/`, `test/factories/`.

Note: `factory_bot_rails`, `faker`, `vcr`/`webmock`, `capybara`, `database_cleaner`.

---

### Phase 7 — Architectural Patterns: How is the code organized?

Check for these directories beyond standard MVC:

```
app/services/        app/interactors/     app/operations/
app/decorators/      app/presenters/      app/policies/
app/serializers/     app/workers/         app/forms/
app/queries/         app/validators/      app/uploaders/
app/components/      lib/
```

Identify the dominant pattern: fat-model, service-object, interactor-heavy,
or a specific architecture (DDD, Clean Architecture).

---

## Output — Write .claude/PROJECT_REPORT.md

After completing all phases, write `.claude/PROJECT_REPORT.md`.
This file is the persistent project memory. It must be concise, structured,
and contain only what cannot be inferred by reading a single source file.

```markdown
# PROJECT_REPORT
last_updated: <ISO 8601 date>
rails_version: <x.x.x>
ruby_version: <x.x.x>

---

## Stack

- **Database**: postgresql / mysql / sqlite
- **Background jobs**: sidekiq (Redis) / good_job (Postgres) / none
- **Auth**: devise / custom / none
- **Soft deletes**: paranoia / discard / none — affects: <list tables or "all">
- **Key behavior gems**: <only non-obvious ones that change default Rails behavior>

---

## Domain Model

Central hub: <ModelName> — most records relate to this
Key relationships:
- <ModelA> has_many <ModelB> through <join_table>
- <ModelC> belongs_to <ModelD> (polymorphic)

Enums:
- <Model>#status → [pending, active, cancelled]
- <Model>#role → [admin, member, guest]

Multi-tenancy: <tenant column> present on <list tables or "all tables">
STI: <list tables with type column or "none">
Sparse indexes: <list tables with few or no indexes — flag for performance review>

---

## API Surface

Mode: full-stack / hybrid / API-only
Namespaces: <api/v1, admin, etc.>
Mounted engines: <sidekiq web, flipper, etc.>
Notable non-REST actions: <list custom collection/member routes>

---

## Frontend

Strategy: Server-rendered / Hotwire / Hybrid Hotwire+React / API+SPA / Legacy Webpacker
JS pipeline: importmap / webpacker / esbuild / vite
Notes: <any notable component library or CSS framework>

---

## Tests

Framework: RSpec / Minitest
Factories: FactoryBot (spec/factories/) / fixtures
Run all: `bundle exec rspec` / `bin/rails test`
Run single: `bundle exec rspec spec/path/to/file_spec.rb`
System tests: `bundle exec rspec spec/system/`

---

## Architecture

Pattern: <fat model / service objects / interactors / mixed>
Non-standard dirs present: <only those that exist>
Notable conventions: <anything the team does consistently that deviates from Rails defaults>

---

## External Services

<List each third-party integration found in initializers with its purpose>
- Stripe → payments (config/initializers/stripe.rb)
- Sentry → error monitoring (config/initializers/sentry.rb)

---

## Dev Commands

- Start: `bin/dev` / `bin/rails server`
- Console: `bin/rails console`
- Routes: `bin/rails routes`
- Migrate: `bin/rails db:migrate`

---

## Gotchas

<Only document things that cannot be inferred from reading the source>
- <e.g. "Appointments belong to ReferralService, not Patient directly">
- <e.g. "Sidekiq requires Redis on port 6380, not default 6379">
- <e.g. "paranoia is used but discard is being migrated — both coexist">
```

### What NOT to include

- Standard Rails directory structure
- Generic advice
- Everything from Gemfile.lock
- Full schema dump or full route list
- Any path that follows Rails conventions exactly

Keep the file under 250 lines. Every line must be something that saves
a future session from having to re-read a source file.

---

## Quick Reference — Files by Question

| Question | File to read |
|---|---|
| What gems are used? | `Gemfile` |
| What's the data model? | `db/schema.rb` |
| What routes exist? | `config/routes.rb` |
| What's configured at boot? | `config/initializers/*.rb`, `config/application.rb` |
| What frontend stack? | `config/importmap.rb`, `package.json`, `app/javascript/` |
| What test framework? | `spec/` or `test/` presence |
| What architecture? | `app/` subdirs beyond mvc |
| Project summary? | `.claude/PROJECT_REPORT.md` |

**Never** run `find . -name "*.rb" | head -100` or similar broad scans.
Go directly to the file that answers the question.
