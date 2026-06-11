# DHH Code Review Patterns

> Extracted from PR reviews in basecamp/fizzy. Focus: simplicity, directness, Rails conventions, and fighting abstraction.

---

## Core Philosophy: Earn Your Abstractions

### Question Every Layer of Indirection

DHH consistently challenges abstractions that don't justify their existence.

> "I find these explicit classes for the notifier rather anemic. And there's not as much future potential for a million more. Think we're better off inlining them."

> "Good example of how this is getting confusing and very indirect between source and resource. And there just aren't enough variations to warrant this level of indirection."

**The Test**: Ask "Is this abstraction earning its keep?" If you can't point to 3+ variations that need it, inline it.

### "Anemic" Code Should Be Inlined

Methods and classes that don't explain anything or provide meaningful abstraction should be removed.

> "Don't think this method is carrying its weight. Either it needs to explain something or you should just inline."
> "Bit anemic. Would inline."

**Rule**: If a method just wraps another call with no additional logic or explanation, delete it.

---

## Write-Time vs Read-Time Operations

### Compute at Write Time, Not Presentation Time

> "All this manipulation has to happen when you save, not when you present. So data model has to fit something where it can be updated. Otherwise you won't be able to paginate."
> "Would consider storing the current summary as a body here. Then you only compute this when there's a write."

```ruby
# Bad - computing at read time
def thread_entries
  (comments + events).sort_by(&:created_at)
end

# Good - using delegated types with single-table query (enables pagination)
class Message < ApplicationRecord
  delegated_type :messageable, types: %w[Comment EventSummary]
end

bubble.messages.order(:created_at).limit(20)
```

**Why it matters**: Enables pagination, enables caching, removes complexity from views.

---

## Database Over Application Logic

### Prefer DB Constraints Over AR Validations

> "Don't think these validations add much/anything over just having the DB raise an exception if, say, uniqueness constraint is violated... Generally speaking, we've almost entirely stopped using validations like this."

```ruby
# Avoided
validates :code, uniqueness: true

# Preferred — let the database enforce integrity
add_index :join_codes, :code, unique: true
```

**When to validate**: Only when you need user-facing error messages for form display.

### Use AR Counter Caches

> "Should use AR counters."
> "You can lean on the AR counter methods here for a more natural API."

### Use `pluck` Over `map`

> "Use `pluck(:name)` instead of `map(&)`."
> "Don't think you need this accessor if you just use pluck at the callsite."

```ruby
event.assignees.pluck(:name)   # single query, no objects
# not: event.assignees.map(&:name)
```

---

## Naming Principles

### Use Positive Names

> "`not_popped` is pretty cumbersome. Consider something like `unpopped` if staying in the negative or go with something like `active`."

```ruby
scope :active,  -> { where(popped_at: nil) }   # not :not_popped
scope :visible, -> { where(deleted_at: nil) }  # not :not_deleted
```

### Method Names Should Reflect Return Value

> "`collect` implies that we're returning an array of mentions (as #collect). Would use `create_mentions` when you don't care about the return value."

### Consistent Domain Language

> "`container` strikes me as out of context with mentions. We don't use that term anywhere else."

---

## Rails Conventions

### StringInquirer for Action Predicates

> "Bit too heavy-handed. Better to make action return a StringInquirer. Then you can do `event.action.completed?`."

```ruby
class Event < ApplicationRecord
  def action
    self[:action].inquiry
  end
end

event.action.completed?   # instead of event.action == "completed"
event.action.published?
```

### Use `after_save_commit` Shorthand

> "You can use `after_save_commit` instead of `after_commit on: %i[ create update ]`."

### Delegate for Lazy Loading

> "Why not just delegate :user to :session? Then you get to lazy load it too."

### Touch Chains for Cache Invalidation

> "Needs to `touch: true` to bust caching."

---

## View Patterns

### Extract View Logic to Helpers, Not Partials

> "Something about this feels slightly off. Maybe it's the fact that the partials are really more just like helper methods. There's virtually no html in them."
> "Smells like this should be a method on the EventSummary. There's no markup here. And there's feature envy."

**Pattern**: If a partial has virtually no HTML and is mostly Ruby logic:
1. A helper method (if view-specific)
2. A model method (if it's domain logic)

### Helpers Should Receive Explicit Parameters

> "Generally consider it a smell to have helpers refer to magical ivars. Better to pass in the ivar to make that dependency explicit."

```ruby
# Bad - relies on @bubble ivar
def bubble_activity_count
  @bubble.comments_count + @bubble.events_count
end

# Good - explicit dependency
def bubble_activity_count(bubble)
  bubble.comments_count + bubble.events_count
end
```

### Turbo Stream Canonical Style

> "This should also use the canonical style: `turbo_stream.update [ @card, :new_comment ], partial: \"cards/comments/new\", locals: { card: @card }`"

```ruby
turbo_stream.update [@card, :new_comment], partial: "cards/comments/new", locals: { card: @card }
```

---

## Be Explicit Over Clever

### Avoid Introspection Magic

> "Actually, I think this is too clever. There are only two different types of cards that have mentionable content: cards and comments. I would find a way to be explicit about this."
> "Good example where the method_missing actually works a bit against you. You're probably better off with a `case event.action`."

**Pattern**: When there are only 2-3 cases, explicit `case` statements or defined methods beat metaprogramming.

### Avoid Unnecessary Base Class Extensions

> "This is a bit too much. Should just put this method on the Reaction class. Should be very hesitant to add base class extensions."

---

## API Design

### Implicit Respond To

> "We don't need a respond_to block when the action has templates for both formats."

```ruby
# Just have show.html.erb and show.json.jbuilder — Rails handles it
def show; end
```

### Prefer `head :no_content` for Updates

> "Why use the `render :show` here vs `head :no_content`?"

---

## Routing

### Use `My::` Namespace for Current User Resources

> "This should be `My::IdentitiesController`. We're putting everything that derives from `Current.identity` on that to imply there won't be a /identities/x."

---

## Migrations

### Migrations Can Reference Models

> "Interacting directly with models present at the time of the migration is totally fine."

```ruby
# Fine in migrations:
Notification.update_all(source_type: "Event")
```

---

## Testing Philosophy

### Avoid Test-Induced Design Damage

> "I think that would then qualify as test-induced design damage. Better replace that with a mock or even better just a fixture session. We should never let our desire for ease of testing bleed into the application itself."

---

## Key Takeaways

1. **Abstractions must earn their keep** — If it doesn't explain or enable variations, inline it
2. **Write time > Read time** — Compute summaries and sort keys when saving, not presenting
3. **Database over AR** — Prefer DB constraints over ActiveRecord validations
4. **Positive names** — Use `active` not `not_deleted`
5. **Explicit over clever** — Case statements beat metaprogramming for 2-3 variations
6. **StringInquirer for predicates** — `action.completed?` over string comparisons
7. **Touch chains** — Use `touch: true` for cache invalidation
8. **Helpers take params** — Don't rely on magical ivars
9. **Targets over selectors** — In Stimulus, use data-*-target
10. **Tests shouldn't shape design** — Never add code just for testability
