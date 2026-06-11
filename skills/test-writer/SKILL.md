---
name: test-writer
description: |
  Write, review, or improve RSpec tests in Ruby on Rails projects. Use when:
  tests are needed for new code, existing specs need review, coverage is
  missing, or test quality is poor. Reads .claude/PROJECT_REPORT.md first to
  match the project's framework, factory setup, and architectural patterns.
  Based on Marston & Dees "Effective Testing with RSpec 3", RuboCop RSpec
  Style Guide, and Rails testing conventions.
  Do NOT use for: Minitest projects (uses RSpec patterns), non-Ruby tests
  (Jest, Vitest, pytest), end-to-end browser tests outside Capybara/system,
  or load/performance testing.
---

# Test Writer

Write tests that are worth the bytes they're written in.
A test must do one of three things or it shouldn't exist:
increase confidence, document behavior, or prevent regression.
If it does none of those, delete it.

**Source principles:**
- *Effective Testing with RSpec 3* — Myron Marston & Erin Dees
- RuboCop RSpec Style Guide (rspec.rubystyle.guide)
- Rails testing conventions

---

## Entry Point — Read Context Before Writing

Before writing a single spec, check these in order:

**1. Read `.claude/PROJECT_REPORT.md`**
- What test framework? (RSpec / Minitest — this skill covers RSpec)
- FactoryBot or fixtures?
- `spec/support/` — what shared contexts and helpers exist?
- What architectural patterns? (service objects, interactors, concerns)
- What is the dominant test style in `spec/`?

**2. Identify the spec type needed**

| What to test | Spec type | Location |
|---|---|---|
| Business logic, models | Unit spec | `spec/models/`, `spec/services/` |
| Multiple real layers together | Integration spec | `spec/requests/`, `spec/jobs/` |
| Full user workflow | Acceptance spec | `spec/system/` |
| Isolated component with doubles | Unit spec | `spec/` matching `app/` structure |

**3. Get the spec passing first, then refactor**
Never extract shared setup while red. Get green, then DRY up.

---

## Reference Files — Read the One That Matches the Task

- `references/spec-types.md` — Acceptance, unit, integration spec patterns +
  Rails-specific (models, request specs, job specs)
- `references/structure-and-doubles.md` — Naming/full-sentence rule, `let` vs
  `before`, declaration order, verifying doubles, spy pattern, metadata
- `references/matchers-factories-deps.md` — Precise matchers, change matcher,
  composed/custom matchers, shared examples, FactoryBot, time freezing,
  HTTP stubbing/VCR

---

## Core Rules — Always Apply

1. **Verifying doubles only.** `instance_double` / `class_double` / `object_double`.
   Plain `double` is forbidden — it doesn't catch interface drift.
2. **Never stub the subject under test.** It's a design smell — extract the
   dependency.
3. **No `allow_any_instance_of`.** Use dependency injection instead.
4. **No instance variables (`@var`) in specs.** Always `let`.
5. **No `before(:all)` / `before(:context)`.** State leaks between examples.
6. **Never hit real external services.** Stub with WebMock or VCR.
7. **Never depend on real `Time.now`.** Freeze time explicitly.
8. **Every `context` has an opposite.** A lone `context` is a code smell.
9. **`described_class`, not hardcoded class names.**
10. **Prefer `build_stubbed` > `build` > `create`** — only `create` when you need
    persistence.

---

## Anti-Patterns — Never Do

- `allow_any_instance_of` / `expect_any_instance_of` — use dependency injection
- Plain `double` instead of `instance_double` / `class_double` — no interface checking
- Instance variables (`@var`) in specs — use `let`
- `before(:all)` / `before(:context)` — state leaks between examples
- Iterators to generate examples (`[:a, :b].each { |x| it ... }`) — untraceable failures
- `sleep` in specs for async — use `have_enqueued_mail`, `perform_enqueued_jobs`, or `wait_for`
- Hitting real external services — always stub
- Testing `attr_reader` / `attr_writer` directly — test behavior, not DSL
- Stubbing the subject under test — design smell, extract the dependency
- Constants declared inside example groups — they leak into global namespace
- `be` without arguments — too generic, use `be_truthy`, `be_nil`, or a predicate

---

## Output — Test Review Report

When reviewing existing specs, always produce this structured output:

```
SPEC FILE: <path>
Spec type: unit / integration / acceptance
Current state: passing / failing / unknown

Issues found (by priority):
  CRITICAL — test gives false confidence
    - <issue> at line <N>: <why it's wrong>
  WARNING — test is fragile or misleading
    - <issue> at line <N>: <recommendation>
  STYLE — readability or convention violation
    - <issue> at line <N>: <fix>

Missing coverage:
  - <behavior> is not tested

Recommended additions:
  - <spec description> — reason: <what it catches>

DHH Verdict: <one sentence on the overall test quality>
```
