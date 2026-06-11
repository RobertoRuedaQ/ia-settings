# Redis Coordination, Performance, and Idempotency

How to use Redis as the coordination backbone, configure queues and retries,
keep jobs small, and design every job to be safely retryable.

---

## Redis as Coordination Backbone

Redis is not just a job queue — it is the coordination layer for everything
that needs to be shared across workers, processes, or time.

### Counters and progress tracking

```ruby
# frozen_string_literal: true

class BatchImportJob < ApplicationJob
  PROGRESS_TTL = 2.hours.to_i

  def perform(import_id, record_ids)
    total = record_ids.size
    progress_key = "import:#{import_id}:progress"
    failed_key   = "import:#{import_id}:failed"

    redis.setex(progress_key, PROGRESS_TTL, 0)

    record_ids.each do |id|
      ImportRecord.find(id).process!
      redis.incr(progress_key)
    rescue StandardError => e
      redis.rpush(failed_key, id)
      redis.expire(failed_key, PROGRESS_TTL)
    end
  end

  # Query from anywhere: ImportJob.progress(import_id)
  def self.progress(import_id)
    redis_client.get("import:#{import_id}:progress").to_i
  end

  def self.failed_ids(import_id)
    redis_client.lrange("import:#{import_id}:failed", 0, -1)
  end

  private

  def redis
    Sidekiq.redis_client
  end

  def self.redis_client
    Sidekiq.redis_client
  end
end
```

### Rate limiting with Redis (external API calls)

```ruby
# frozen_string_literal: true

class ExternalApiJob < ApplicationJob
  RATE_LIMIT     = 100   # max calls
  RATE_WINDOW    = 60    # seconds
  RETRY_DELAY    = 5     # seconds when throttled

  def perform(resource_id)
    enforce_rate_limit!
    ExternalApi.call(resource_id)
  end

  private

  def enforce_rate_limit!
    key     = "rate_limit:external_api:#{Time.current.to_i / RATE_WINDOW}"
    count   = redis.incr(key)
    redis.expire(key, RATE_WINDOW * 2) if count == 1

    return if count <= RATE_LIMIT

    # Re-enqueue with delay instead of raising — preserves retry budget
    self.class.set(wait: RETRY_DELAY.seconds).perform_later(
      *arguments.args,
    )
    raise Sidekiq::Job::Skip
  end

  def redis
    Sidekiq.redis_client
  end
end
```

### Deduplication cache for expensive operations

```ruby
# frozen_string_literal: true

class GenerateReportJob < ApplicationJob
  CACHE_TTL = 30.minutes.to_i

  def perform(report_params_key)
    params      = JSON.parse(redis.get(report_params_key))
    cache_key   = "report:cache:#{Digest::SHA256.hexdigest(params.to_s)}"

    # Skip if already generated recently
    return if redis.exists?(cache_key)

    report = ReportGenerator.call(params)

    redis.setex(cache_key, CACHE_TTL, report.to_json)
    redis.del(report_params_key)
  end

  private

  def redis
    Sidekiq.redis_client
  end
end
```

---

## Performance — Minimal Resource Usage

### Queue strategy

Map queues to resource profiles, not job names:

```yaml
# config/sidekiq.yml
:concurrency: 10
:queues:
  - [critical, 4]   # user-facing, latency-sensitive, small jobs
  - [default, 3]    # standard async work
  - [bulk, 2]       # large batches, scans, reports
  - [mailers, 1]    # email sending
```

**Rules:**
- `critical` — jobs blocking a user response (< 500ms expected)
- `default` — standard async (seconds to minutes)
- `bulk` — anything touching > 1000 records (isolated to prevent starvation)
- Never run bulk jobs on the same concurrency as critical jobs

### Job size — keep jobs small and fast

```ruby
# BAD — one job processes everything (slow, unrecoverable on failure)
class SyncAllUsersJob < ApplicationJob
  def perform
    User.find_each { |u| SyncService.call(u) }
  end
end

# GOOD — orchestrator enqueues one job per record (parallelizable, retryable)
class SyncAllUsersJob < ApplicationJob
  queue_as :bulk

  def perform
    User.select(:id).find_each(batch_size: 1000) do |user|
      SyncUserJob.perform_later(user.id)
    end
  end
end

class SyncUserJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 5

  def perform(user_id)
    user = User.find_by(user_id)
    return unless user  # record may have been deleted — guard, don't raise

    SyncService.call(user)
  end
end
```

### Database query rules inside jobs

```ruby
# frozen_string_literal: true

class ProcessActiveOrdersJob < ApplicationJob
  queue_as :bulk

  def perform
    # SELECT only what you need — never SELECT *
    Order.where(status: :pending)
         .select(:id, :user_id, :total_cents)
         .find_each(batch_size: 500) do |order|
      ProcessOrderJob.perform_later(order.id)
    end
  end
end
```

- Always `select` only the columns the job needs
- Always use `find_each` or explicit `LIMIT/OFFSET` with ordered cursor
- Never use `.all` or `.each` on large scopes
- Wrap multi-step DB operations in transactions only when atomicity is required
- Keep transactions short — never call external services inside a transaction

### Retry configuration

```ruby
# frozen_string_literal: true

class ResilientJob < ApplicationJob
  queue_as :default

  # Exponential backoff: 15s, 1min, 10min, 1hr, 3hr
  sidekiq_options retry: 5

  # Dead set after exhausting retries — visible in Sidekiq UI
  sidekiq_retries_exhausted do |job, exception|
    Rails.logger.error(
      event:      'job_exhausted',
      job_class:  job['class'],
      args:       job['args'],
      error:      exception.message,
    )
    # Optionally: alert, mark record as failed, trigger fallback
  end

  def perform(record_id)
    # ...
  end
end
```

---

## Idempotency — Every Job Must Be Safe to Retry

A job that cannot be safely retried is a liability. Design for at-least-once execution.

```ruby
# frozen_string_literal: true

class ChargeSubscriptionJob < ApplicationJob
  queue_as :critical
  sidekiq_options retry: 3

  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)

    # Guard: skip if already processed (idempotency check)
    return if subscription.charged_for_current_period?

    result = PaymentGateway.charge(
      amount:      subscription.amount_cents,
      customer_id: subscription.customer_gateway_id,
      idempotency_key: "charge:#{subscription_id}:#{subscription.current_period}",
    )

    subscription.record_charge!(result.charge_id)
  rescue PaymentGateway::AlreadyChargedError
    # Idempotency key matched — already charged, record and move on
    subscription.mark_charge_reconciled!
  end
end
```

**Idempotency checklist:**
- Check state before acting — return early if already done
- Pass idempotency keys to external APIs
- Use `find_or_create_by` over `create` when upserting
- Use `update_columns` over `update` when skipping callbacks is intentional
- Never rely on job uniqueness alone — the job system can deliver twice
