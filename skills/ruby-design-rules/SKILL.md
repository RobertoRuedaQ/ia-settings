---
name: ruby-design-rules
description: |
  Sandi Metz's four object-design rules (POODR) for Ruby: classes ≤100 lines,
  methods ≤5 lines, ≤4 parameters per method, controllers instantiate one
  object. Use when refactoring Ruby for maintainability, when a class/method
  feels too big, when the user mentions "POODR" or "Sandi Metz", or as part
  of a Ruby code review.
  Do NOT use for: non-Ruby code, greenfield design questions (use a design
  skill instead), generated files (routes.rb, migrations, schema.rb), DSL
  definitions, or Rails-idiomatic style questions (use `idiomatic-rails-patterns`).
---

# Sandi Metz Rules

Four rules for writing maintainable object-oriented Ruby code.

## The Four Rules

1. **Classes can be no longer than 100 lines of code**
2. **Methods can be no longer than 5 lines of code**
3. **Pass no more than 4 parameters into a method**
4. **Controllers can instantiate only one object**

Break rules only with a good reason or your pair's approval. Minimize violations — if you need 6 lines, that's borderline; if you need 20, reconsider.

---

## Counting Rules

**Class lines** — exclude: class definition, `end`, blank lines, comments
**Method lines** — exclude: method definition, `end`, blank lines, comments
**Parameters** — count keyword args and defaults; do NOT count `&block`

---

## Rule 1: Classes ≤ 100 Lines

**Violation signals**: God objects, mixed responsibilities (business + presentation + persistence)

**Fix strategies**:
- Extract related methods into a new class
- Identify separate responsibilities (Single Responsibility Principle)
- Use composition or modules for shared behavior
- Apply Strategy, Decorator, or Command pattern

---

## Rule 2: Methods ≤ 5 Lines

**Violation signals**: Methods doing multiple things, long conditionals, nested loops, multiple abstraction levels

**Fix strategies**:
- Extract sub-methods with descriptive names (Composed Method pattern)
- Replace conditionals with polymorphism
- Use guard clauses to reduce nesting

```ruby
# Before (7 lines)
def total_price
  base = items.sum(&:price)
  if premium_member?
    discount = base * 0.2
    base - discount
  else
    base
  end
end

# After
def total_price        = base_price - member_discount
def base_price         = items.sum(&:price)
def member_discount    = premium_member? ? base_price * 0.2 : 0
```

---

## Rule 3: ≤ 4 Parameters

**Violation signals**: Configuration data, methods passing data through layers, boolean flags, coordinate data

**Fix strategies**:
- Introduce Parameter Object to group related params
- Use Builder pattern for complex construction
- Consider if the method belongs on a different class

```ruby
# Before (5 parameters)
def create_user(name, email, age, city, country)

# After (2 parameters)
def create_user(personal_info, location)
```

---

## Rule 4: Controllers Instantiate One Object

**Violation signals**: Controllers orchestrating multiple service calls, business logic in actions

**Fix strategies**:
- Extract service objects / use cases
- Apply Command or Facade pattern

```ruby
# Before — multiple instantiations
def create
  order     = Order.new(order_params)
  payment   = PaymentProcessor.new(payment_params)
  inventory = InventoryManager.new
  # ...
end

# After — single entry point
def create
  result = CreateOrder.new(order_params, payment_params).call
  result.success? ? redirect_to(result.order) : render(:new)
end
```

---

## Code Review Workflow

1. **Read** `references/rules.md` for detailed patterns and examples
2. **Measure accurately** using the counting rules above
3. **Prioritize violations**:
   - High: classes > 200 lines, methods > 10 lines, 6+ params, fat controllers
   - Medium: 100–200 line classes, 5–10 line methods, 5 params
   - Low: borderline cases, test files, DSL definitions
4. **Suggest concrete refactorings** — show before/after code
5. **Consider context** — routes.rb, migrations, generated code are exempt

---

## RuboCop Configuration

```yaml
Metrics/ClassLength:
  Max: 100

Metrics/MethodLength:
  Max: 5

Metrics/ParameterLists:
  Max: 4
  MaxOptionalParameters: 3
```

---

## Related Principles

- **Single Responsibility Principle** — each class/method has one reason to change
- **Tell, Don't Ask** — tell objects what to do; don't query their state
- **Law of Demeter** — only talk to your immediate friends
- **Composed Method** — methods at a single level of abstraction

Read `references/rules.md` for full examples and rationale.
