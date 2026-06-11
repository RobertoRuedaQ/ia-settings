# Spec Types

The three Marston & Dees spec types and Rails-specific patterns.

---

## Acceptance specs — outside-in, full stack

Start here when building a new feature. Define what success looks like
from the outside before writing any implementation.

```ruby
# frozen_string_literal: true

# spec/system/expense_tracking_spec.rb
RSpec.describe 'Expense tracking', type: :system do
  scenario 'user records a new expense' do
    sign_in_as create(:user)

    visit new_expense_path
    fill_in 'Amount', with: '42.50'
    fill_in 'Payee',  with: 'Acme Corp'
    click_button 'Record Expense'

    expect(page).to have_text('Expense recorded')
    expect(page).to have_text('Acme Corp')
    expect(page).to have_text('$42.50')
  end

  scenario 'user sees validation errors for missing amount' do
    sign_in_as create(:user)

    visit new_expense_path
    fill_in 'Payee', with: 'Acme Corp'
    click_button 'Record Expense'

    expect(page).to have_text("Amount can't be blank")
  end
end
```

**Rules for acceptance specs:**
- Test the happy path and the most critical failure path
- Do not test every edge case here — that belongs in unit specs
- Use Capybara negative selectors: `have_no_text` not `not_to have_text`
- Keep them slow-test-safe: tag with `type: :system` for conditional DB cleanup

---

## Unit specs — isolated, fast, design-driven

Use test doubles to isolate the unit under test from its dependencies.
Fast. No database when possible. These are the specs that give design feedback.

```ruby
# frozen_string_literal: true

# spec/services/expense_recorder_spec.rb
RSpec.describe ExpenseRecorder do
  # Always use instance_double / class_double — never plain double
  # Verifying doubles catch interface drift at test time, not runtime
  let(:ledger)  { instance_double(Ledger) }
  let(:expense) { { 'amount' => '42.50', 'payee' => 'Acme Corp' } }

  subject(:recorder) { described_class.new(ledger:) }

  describe '#record' do
    context 'when the expense is valid' do
      before do
        allow(ledger).to receive(:record).with(expense).and_return(
          instance_double(Ledger::Result, success?: true, expense_id: 42),
        )
      end

      it 'returns a successful result' do
        result = recorder.record(expense)
        expect(result).to be_success
      end

      it 'returns the persisted expense id' do
        result = recorder.record(expense)
        expect(result.expense_id).to eq(42)
      end
    end

    context 'when the expense is invalid' do
      before do
        allow(ledger).to receive(:record).with(expense).and_return(
          instance_double(Ledger::Result, success?: false, error_message: 'Amount is missing'),
        )
      end

      it 'returns a failed result' do
        result = recorder.record(expense)
        expect(result).not_to be_success
      end

      it 'returns the error message' do
        result = recorder.record(expense)
        expect(result.error_message).to eq('Amount is missing')
      end
    end
  end
end
```

---

## Integration specs — real dependencies, real database

Use these to verify that the layers work together. No doubles.
Real database. Real ActiveRecord. Real Redis if the code uses it.

```ruby
# frozen_string_literal: true

# spec/requests/expenses_spec.rb
RSpec.describe 'Expenses API', type: :request do
  describe 'POST /expenses' do
    let(:user)    { create(:user) }
    let(:headers) { auth_headers_for(user) }

    context 'when the expense data is valid' do
      let(:params) { { expense: { amount: '42.50', payee: 'Acme Corp' } } }

      it 'returns 201 Created' do
        post expenses_path, params:, headers:
        expect(response).to have_http_status(:created)
      end

      it 'persists the expense' do
        expect {
          post expenses_path, params:, headers:
        }.to change(Expense, :count).by(1)
      end

      it 'returns the expense id' do
        post expenses_path, params:, headers:
        expect(response.parsed_body['expense_id']).to be_a(Integer)
      end
    end

    context 'when the expense data is invalid' do
      let(:params) { { expense: { payee: 'Acme Corp' } } }

      it 'returns 422 Unprocessable Entity' do
        post expenses_path, params:, headers:
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not persist the expense' do
        expect {
          post expenses_path, params:, headers:
        }.not_to change(Expense, :count)
      end
    end
  end
end
```

---

## Rails-Specific Patterns

### Models — test behavior, not implementation

```ruby
RSpec.describe Expense, type: :model do
  subject(:expense) { build(:expense) }

  # Validate the factory is valid — catches factory drift
  it 'has a valid factory' do
    expect(expense).to be_valid
  end

  describe 'validations' do
    describe '#amount' do
      it 'is required' do
        expense.amount = nil
        expense.valid?
        expect(expense.errors[:amount]).to include("can't be blank")
      end

      it 'must be positive' do
        expense.amount = -1
        expense.valid?
        expect(expense.errors[:amount]).to include('must be greater than 0')
      end
    end
  end

  describe '.recent' do
    it 'returns expenses ordered by created_at descending' do
      older = create(:expense, created_at: 2.days.ago)
      newer = create(:expense, created_at: 1.day.ago)

      expect(described_class.recent).to eq([newer, older])
    end
  end
end
```

### Request specs over controller specs

Controller specs test implementation details. Request specs test behavior.

```ruby
# bad — controller spec
RSpec.describe ExpensesController, type: :controller do
  describe 'GET #index' do
    it 'assigns @expenses' do
      get :index
      expect(assigns(:expenses)).to be_a(ActiveRecord::Relation)
    end
  end
end

# good — request spec
RSpec.describe 'GET /expenses', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'returns the user expenses' do
    create_list(:expense, 3, user:)
    get expenses_path
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['expenses'].length).to eq(3)
  end
end
```

### Job specs

```ruby
RSpec.describe SyncUserDataJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'enqueues on the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'calls the sync service with the user' do
      sync_service = instance_double(UserSyncService, call: true)
      allow(UserSyncService).to receive(:new).with(user).and_return(sync_service)

      described_class.perform_now(user.id)

      expect(sync_service).to have_received(:call)
    end

    it 'does nothing when the user does not exist' do
      expect { described_class.perform_now(-1) }.not_to raise_error
    end
  end
end
```
