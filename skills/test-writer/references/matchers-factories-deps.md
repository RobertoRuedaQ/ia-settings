# Matchers, FactoryBot, and External Dependencies

Precision matchers; factory patterns; time, HTTP, and shared example utilities.

---

## Matchers — Precision and Readability

### Use the most precise matcher available

```ruby
# bad — too generic
expect(result).to be_truthy
expect(errors).not_to be_empty
expect(items.length).to eq(3)

# good — precise
expect(result).to be_success        # predicate matcher
expect(errors).not_to be_empty      # or:
expect(errors).to be_present        # Rails predicate
expect(items).to have(3).items      # or:
expect(items.count).to eq(3)
```

### Change matcher for side effects

```ruby
# bad — incidental state, fragile
it 'creates an expense' do
  post :create, params: valid_params
  expect(Expense.count).to eq(1)   # breaks if other tests leave records
end

# good — delta-based, resilient
it 'creates an expense' do
  expect {
    post :create, params: valid_params
  }.to change(Expense, :count).by(1)
end

# good — multiple changes with aggregate_failures
it 'creates an expense and notifies the user', :aggregate_failures do
  expect {
    post :create, params: valid_params
  }.to change(Expense, :count).by(1)
    .and change(Notification, :count).by(1)
end
```

### Compose matchers for complex assertions

```ruby
# Instead of multiple expectations for one logical assertion
expect(response.parsed_body).to include(
  'id'     => be_a(Integer),
  'amount' => '42.50',
  'status' => match(/active|pending/),
)
```

### Custom matchers for repeated logic

When the same assertion appears three or more times, extract it.

```ruby
# spec/support/matchers/be_a_valid_expense.rb
RSpec::Matchers.define :be_a_valid_expense do
  match do |response|
    parsed = response.parsed_body
    parsed.key?('id') &&
      parsed['amount'].match?(/\A\d+\.\d{2}\z/) &&
      parsed['payee'].present?
  end

  failure_message do |response|
    "expected response to be a valid expense, got: #{response.body}"
  end
end

# Usage
it 'returns a valid expense' do
  post expenses_path, params:, headers:
  expect(response).to be_a_valid_expense
end
```

---

## Shared Examples — When and How

Use shared examples to eliminate duplication across specs that test
the same contract. Do not use them to be DRY prematurely.

```ruby
# spec/support/shared_examples/a_paginated_resource.rb
RSpec.shared_examples 'a paginated resource' do
  context 'when page param is provided' do
    it 'returns the requested page' do
      get path, params: { page: 2, per_page: 5 }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['meta']['current_page']).to eq(2)
    end
  end

  context 'when page param is absent' do
    it 'returns the first page' do
      get path
      expect(response.parsed_body['meta']['current_page']).to eq(1)
    end
  end
end

# Usage
RSpec.describe 'Expenses API', type: :request do
  let(:path) { expenses_path }

  it_behaves_like 'a paginated resource'
end
```

**When to use shared examples:**
- Same behavior contract tested in multiple specs (e.g. pagination, authorization)
- Policy tests that apply to multiple resources
- Serializer contracts

**When NOT to use shared examples:**
- Just to reduce line count
- When the shared behavior differs subtly between uses — just write separate specs

---

## FactoryBot Patterns

### Keep factories minimal — build only what's required

```ruby
# bad — factory that creates unnecessary associations
FactoryBot.define do
  factory :expense do
    amount { 42.50 }
    payee  { 'Acme Corp' }
    user                       # creates a User even when not needed
    category                   # creates a Category even when not needed
    association :receipt_image # always uploads a file in tests
  end
end

# good — minimal factory, associations on demand
FactoryBot.define do
  factory :expense do
    amount { 42.50 }
    payee  { 'Acme Corp' }
    association :user

    trait :with_category do
      association :category
    end

    trait :with_receipt do
      after(:build) do |expense|
        expense.receipt_image.attach(
          io: File.open(Rails.root.join('spec/fixtures/files/receipt.pdf')),
          filename: 'receipt.pdf',
        )
      end
    end
  end
end
```

### Never use `create` when `build` or `build_stubbed` suffices

```ruby
# Use build_stubbed for unit specs that don't hit the database
let(:user) { build_stubbed(:user, :admin) }

# Use build when validations need to run but persistence doesn't
let(:invalid_expense) { build(:expense, amount: nil) }

# Use create only in integration specs and system specs
let(:user) { create(:user) }
```

---

## Time, HTTP, and External Dependencies

### Always freeze time explicitly

```ruby
# bad — test depends on real Time.now, breaks under load or timezone changes
it 'expires after 24 hours' do
  token = create(:auth_token)
  travel 25.hours
  expect(token).to be_expired
end

# good — explicit, readable, uses Rails travel helper
it 'expires after 24 hours' do
  freeze_time do
    token = create(:auth_token)
    travel 25.hours
    expect(token).to be_expired
  end
end
```

### Always stub external HTTP — never hit real services

```ruby
# spec/support/vcr.rb
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data('<API_KEY>') { ENV.fetch('STRIPE_API_KEY') }
end

# Usage in specs
it 'charges the customer', :vcr do
  result = PaymentService.charge(amount: 4250, customer_id: 'cus_123')
  expect(result).to be_success
end

# For simple stubs without VCR
before do
  stub_request(:post, 'https://api.stripe.com/v1/charges')
    .to_return(status: 200, body: fixture('stripe_charge_success.json'))
end
```
