---
name: idiomatic-rails-patterns
description: |
  Idiomatic Rails patterns derived from 37signals/Basecamp (Fizzy codebase):
  concerns over service objects, state-as-records, DB constraints over AR
  validations, Hotwire response style, "abstractions must earn their keep."
  Use when writing or reviewing Rails models, controllers, views, Hotwire/
  Turbo Stream responses, or when asked to follow DHH/37signals patterns.
  Do NOT use for: non-Rails projects, libraries/gems where 37signals patterns
  don't apply, projects that have explicitly adopted a different architecture
  (DDD, hexagonal, service-object-heavy), or pure quality reviews (use
  `ruby-design-rules` for that).
---

# 37signals Style Guide

Patterns derived from analysis of 37signals' Fizzy codebase. Representative, not authoritative —
these reflect observed conventions, not an official 37signals document.

> **Testing note:** 37signals uses Minitest with fixtures. This project uses **RSpec with FactoryBot**.
> Always use the `test-writer` skill for tests. Do not apply the minitest patterns from this guide.

---

## Topic Map — Read the Reference File That Matches the Task

### Core Rails Patterns
- `references/models.md` — Concerns, state-as-records, PORO patterns, scope naming
- `references/controllers-basics.md` — Thin-controllers principle, minimal ApplicationController, authorization split, concern composition rules
- `references/controllers-resource-concerns.md` — Resource-scoping concerns (CardScoped/BoardScoped/ColumnScoped) and FilterScoped
- `references/controllers-cross-cutting-concerns.md` — Request context (CurrentRequest/Timezone/Platform), security headers (CSRF, robots), Turbo/view concerns (TurboFlash, ViewTransitions)
- `references/database.md` — UUIDs, state records, Solid Queue/Cache/Cable, index strategy
- `references/development-philosophy.md` — Ship/validate/refine, Rails over abstractions, DHH review themes

### Frontend & Realtime
- `references/hotwire-turbo.md` — Turbo Frames, Streams, Morphing, Broadcasts, Permanent, Testing, Flash helper
- `references/hotwire-stimulus.md` — Stimulus best practices, timer cleanup, timing helpers, localStorage persistence, cached-fragment personalization, progressive installation
- `references/hotwire-controllers.md` — Reusable Stimulus controllers: dialog, clipboard, hotkey, navigable list, auto-submit, auto-save, lazy-load, drag-and-drop
- `references/actioncable.md` — WebSocket channel patterns, broadcasting, subscriptions

### What to Avoid
- `references/what-they-avoid.md` — No Devise, no Pundit, no service objects, no ViewComponent, no RSpec (use RSpec anyway per project convention)

### Performance
- `references/performance.md` — N+1 prevention, counter caches, pagination, Puma tuning

### DHH Code Review Patterns
- `references/dhh-patterns.md` — Earn abstractions, write-time vs read-time, StringInquirer, DB over AR validations, naming, Turbo Stream style

---

## Core Philosophy (Always Apply)

### Abstractions Must Earn Their Keep
Before extracting a class, module, or method, ask: does this abstraction explain something or enable variations? If you can't point to 3+ real differences, inline it.

- If a method just wraps another call with no additional logic → delete it
- If a class has no behavior of its own → merge it with the caller
- Rule of three: duplicate twice before abstracting

### Vanilla Rails Over Gems
Before adding a dependency:
1. Can vanilla Rails do this?
2. Is the complexity worth the benefit?
3. Will we need to maintain this dependency?

### Ship, Validate, Refine
Merge prototype-quality code to validate with real usage before cleanup. Don't polish prematurely.

---

## Models — Key Patterns

### Concerns for Horizontal Behavior

Fat models decomposed into focused concerns. Each concern handles one capability:

```ruby
class Card < ApplicationRecord
  include Assignable, Closeable, Watchable, Taggable, Eventable
end

# app/models/card/closeable.rb
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy
    scope :closed, -> { joins(:closure) }
    scope :open, -> { where.missing(:closure) }
  end

  def close(user: Current.user)
    transaction do
      create_closure!(user: user)
      track_event :closed, creator: user
    end
  end

  def closed? = closure.present?
end
```

Guidelines: 50–150 lines per concern, cohesive, named for the capability (`Closeable` not `ClosureManagement`).

### State as Records, Not Booleans

```ruby
# Bad — boolean column
scope :closed, -> { where(closed: true) }

# Good — separate record (gives you who + when for free)
class Closure < ApplicationRecord
  belongs_to :card, touch: true
  belongs_to :user
end

scope :closed, -> { joins(:closure) }
scope :open,   -> { where.missing(:closure) }
```

### Default Values via Lambdas

```ruby
belongs_to :account, default: -> { board.account }
belongs_to :creator, class_name: "User", default: -> { Current.user }
```

### Minimal Validations

Prefer DB constraints. Only validate when you need user-facing error messages for forms.

```ruby
validates :name, presence: true   # only if needed for form display
add_index :codes, :value, unique: true  # DB constraint enforces uniqueness
```

### Scopes Named for Business Concepts

```ruby
scope :active,     -> { where.missing(:pop) }     # not :without_pop
scope :unassigned, -> { where.missing(:assignments) }
scope :golden,     -> { joins(:goldness) }
```

### POROs Under Model Namespace

For presentation logic or complex operations that don't need persistence:

```ruby
class Event::Description
  def initialize(event) = @event = event
  def to_s = case @event.action when "closed" then ...
end

class User::Filtering
  def initialize(user, filter) = @user, @filter = user, filter
  def boards = @user.boards.accessible
end
```

---

## Controllers — Key Patterns

### Thin Controllers, Rich Models

```ruby
class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    @card.close           # all logic in model
    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json         { head :no_content }
    end
  end
end
```

### Concerns as Composable Vocabulary

```ruby
module CardScoped
  extend ActiveSupport::Concern
  included do
    before_action :set_card, :set_board
  end

  private
    def set_card  = @card  = Current.user.accessible_cards.find_by!(number: params[:card_id])
    def set_board = @board = @card.board

    def render_card_replacement
      render turbo_stream: turbo_stream.replace([@card, :card_container],
        partial: "cards/container", method: :morph, locals: { card: @card.reload })
    end
end
```

Concerns can include other concerns. Use `before_action` in `included` block. Provide shared private methods.

### Authorization: Controller Checks, Model Defines

```ruby
before_action :ensure_permission, only: [:destroy]

private
  def ensure_permission
    head :forbidden unless Current.user.can_administer_card?(@card)
  end
```

### `params.expect` (Rails 7.1+)

```ruby
params.expect(card: [:title, :description, { tag_ids: [] }])
# Returns 400 instead of 500 for bad params
```

---

## Database — Key Patterns

### State Records over Booleans (see models section)

### No Soft Deletes

Records are deleted, not marked deleted. Use event/audit logs for history.

### Counter Caches

```ruby
belongs_to :board, counter_cache: true
# migration: add_column :boards, :cards_count, :integer, default: 0
```

### Touch Chains for Cache Invalidation

```ruby
class Comment < ApplicationRecord
  belongs_to :card, touch: true  # card.updated_at bumped on comment change
end
```

### Solid Stack (No Redis)

```ruby
gem "solid_queue"   # background jobs
gem "solid_cache"   # fragment caching
gem "solid_cable"   # WebSockets
```

---

## DHH Code Review — Quick Reference

Read `references/dhh-patterns.md` for the full set. Key patterns to apply immediately:

| Pattern | Rule |
|---------|------|
| Abstractions | If you can't name 3+ variations that need it, inline it |
| Write vs Read time | Pre-compute at save time, not at render time |
| StringInquirer | `event.action.completed?` not `event.action == "completed"` |
| Naming | `active` not `not_deleted`; `unpopped` not `not_popped` |
| AR counter caches | Use them; don't count via `map` |
| `pluck` | `model.assoc.pluck(:name)` not `model.assoc.map(&:name)` |
| DB constraints | Prefer over AR validations when no form message needed |
| `after_save_commit` | Not `after_commit on: %i[create update]` |
| Helpers | Always take explicit params; never rely on `@ivars` |
| Turbo Stream | Use canonical array style: `turbo_stream.update [@card, :new_comment], partial: "..."` |
