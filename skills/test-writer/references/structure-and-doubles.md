# Structure, Organization, and Doubles

How to lay out an example group; how to use verifying doubles.

---

## Describe / context / it naming — the full sentence rule

The concatenation of all nested descriptions must read as a sentence.

```ruby
# bad — reads: "User #authenticate when credentials valid returns token"
describe User do
  describe '#authenticate' do
    context 'when credentials valid' do
      it 'returns token' do ...

# good — reads: "User#authenticate when credentials are valid returns an auth token"
describe User do
  describe '#authenticate' do
    context 'when credentials are valid' do
      it 'returns an auth token' do ...
```

**Naming rules:**
- Class methods: `describe '.method_name'`
- Instance methods: `describe '#method_name'`
- Contexts: start with `when`, `with`, `without`, `given`
- Examples: third person present tense, no "should"
- Keep `it` descriptions under 60 characters

---

## Declaration order within an example group

```ruby
RSpec.describe Article do
  # 1. subject (first, always)
  subject(:article) { build(:article) }

  # 2. let / let!
  let(:author) { create(:user) }

  # 3. before / after
  before { article.update!(author:) }

  # 4. describes and contexts
  describe '#publish' do
    # ...
  end
end
```

---

## Context always has an opposite

Every context must have a matching negative counterpart.
A lone context is a code smell — either the other case is missing or
the context has no purpose.

```ruby
# bad — what happens when display_name is NOT present?
context 'when display_name is present' do
  it 'returns the display name' do ...
end

# good
context 'when display_name is present' do
  it 'returns the display name' do ...
end

context 'when display_name is not present' do
  it 'returns nil' do ...
end
```

---

## `let` vs `before` vs helper methods

```ruby
# Use let for data shared across examples in a group (lazy, memoized)
let(:user) { create(:user, :admin) }

# Use let! when the object must exist even if not referenced (e.g. for DB count checks)
let!(:existing_record) { create(:expense) }

# Use before for setup that has side effects (stubbing, state changes)
before { allow(PaymentGateway).to receive(:charge).and_return(success_result) }

# Use helper methods for complex object construction used in one example
def create_expense_with_line_items(count:)
  create(:expense).tap do |expense|
    create_list(:line_item, count, expense:)
  end
end
```

Never use instance variables (`@var`) in specs. Always `let`.

---

## Test Doubles — Marston's Verifying Doubles

Always use verifying doubles. They catch interface drift when the real
class changes but the double doesn't.

```ruby
# NEVER — plain double, no interface checking
allow(double('User')).to receive(:name).and_return('Alice')

# ALWAYS — verifying instance double
let(:user) { instance_double(User, name: 'Alice', admin?: false) }

# ALWAYS — verifying class double
let(:mailer) { class_double(UserMailer) }
before { allow(mailer).to receive(:welcome).and_return(double(deliver_later: true)) }

# ALWAYS — verifying object double (when you have an instance)
let(:article) { object_double(Article.new, valid?: true) }
```

**Never stub the subject under test.** If you need to stub a method on the
object you're testing, that's a design smell — extract the dependency.

**Never use `allow_any_instance_of`.** It signals the object is doing too much.
Use dependency injection instead.

### Spy pattern for verifying messages were sent

```ruby
# Use spies when you want to verify a message was received after the fact
it 'sends a welcome email after registration' do
  mailer_spy = instance_spy(UserMailer)
  allow(UserMailer).to receive(:with).and_return(mailer_spy)

  UserRegistration.call(email: 'alice@example.com')

  expect(mailer_spy).to have_received(:welcome_email).once
end
```

---

## Metadata and Suite Organization

### Tag slow specs for selective running

```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.filter_run_excluding :slow unless ENV['RUN_SLOW_SPECS']
end

# Usage
describe 'full report generation', :slow do
  # ...
end
```

### Use `aggregate_failures` for related assertions

```ruby
describe 'response shape', :aggregate_failures do
  before { post expenses_path, params:, headers: }

  it 'returns the expected shape' do
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('id', 'amount', 'payee')
    expect(response.parsed_body['amount']).to eq('42.50')
  end
end
```

### `described_class` over hardcoded class names

```ruby
# bad — breaks silently if the file is moved or renamed
let(:service) { UserSyncService.new(user) }

# good — always refers to the class being described
let(:service) { described_class.new(user) }
```
