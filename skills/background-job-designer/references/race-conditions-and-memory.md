# Race Conditions and Memory Safety

Race condition mitigation, distributed locking, optimistic locking, uniqueness,
and the five mandatory memory-leak prevention rules.

---

## Race Condition Prevention — Mandatory Checklist

Race conditions in jobs are silent. They don't raise exceptions — they produce
wrong data that gets discovered weeks later. Treat every job as concurrent by default.

### Distributed locking with Redis

Use Redis-based locks for any job that must not run in parallel for the same resource.
Never use database advisory locks in jobs — they don't release on worker crash.

```ruby
# frozen_string_literal: true

class ProcessOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    lock_key = "lock:process_order:#{order_id}"
    lock_ttl = 5.minutes.to_i

    acquired = redis.set(lock_key, worker_id, nx: true, ex: lock_ttl)
    return unless acquired

    begin
      order = Order.find(order_id)
      # ... process
    ensure
      release_lock(lock_key)
    end
  end

  private

  def release_lock(key)
    # Lua script: only release if we own the lock (atomic check-and-delete)
    script = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA
    redis.eval(script, keys: [key], argv: [worker_id])
  end

  def worker_id
    @worker_id ||= "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
  end

  def redis
    Sidekiq.redis_client
  end
end
```

**Rules:**
- Always use Lua scripts for check-and-release — never GET + DEL (not atomic)
- TTL must exceed realistic max job duration + buffer
- Use `nx: true` (set if not exists) — never SET unconditionally
- Include hostname + pid + thread in lock value to identify the owner
- Always release in `ensure` — never assume happy path

---

## Optimistic locking for record updates

When multiple jobs may update the same record:

```ruby
# frozen_string_literal: true

# Migration: add_column :orders, :lock_version, :integer, default: 0, null: false

class UpdateOrderStatusJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 3

  def perform(order_id, new_status)
    order = Order.find(order_id)
    order.update!(status: new_status)
  rescue ActiveRecord::StaleObjectError
    # Another process updated first — re-enqueue with fresh state
    self.class.perform_later(order_id, new_status)
  end
end
```

---

## Uniqueness enforcement with Sidekiq

Prevent duplicate jobs from being enqueued for the same resource:

```ruby
# Gemfile: gem 'sidekiq-unique-jobs'

# frozen_string_literal: true

class SyncUserDataJob < ApplicationJob
  queue_as :default

  sidekiq_options(
    lock: :until_executed,
    lock_args_method: ->(args) { [args.first] }, # lock per user_id
    on_conflict: :reschedule,
  )

  def perform(user_id)
    # ...
  end
end
```

**Lock strategies:**
- `until_executing` — prevents duplicate enqueue, allows parallel execution
- `until_executed` — one job per args until fully complete (safest for data mutations)
- `while_executing` — allow enqueue, prevent parallel execution
- `on_conflict: :reschedule` — requeue instead of drop (preferred over `:log`)

---

## Memory Leak Prevention — Mandatory Rules

Memory leaks in Sidekiq workers are invisible until the process OOMs at 2am.
Every rule below exists because someone learned it the hard way.

### Rule 1 — Never hold object references across job boundaries

```ruby
# BAD — class-level cache holds references forever
class ReportJob < ApplicationJob
  @@processed_ids = []  # grows forever, never GC'd

  def perform(record_id)
    @@processed_ids << record_id
  end
end

# GOOD — use Redis for cross-job state, not class variables
class ReportJob < ApplicationJob
  def perform(record_id)
    redis.sadd('report:processed_ids', record_id)
  end
end
```

### Rule 2 — Stream large datasets, never load into memory

```ruby
# BAD — loads entire table into memory
def perform
  User.where(active: true).each do |user|
    process(user)
  end
end

# GOOD — find_each uses cursor-based batching (default batch_size: 1000)
def perform
  User.where(active: true).find_each(batch_size: 500) do |user|
    process(user)
  end
end

# BETTER for very large sets — explicit cursor with Redis checkpoint
def perform(cursor_id = 0)
  batch = User.where(active: true).where('id > ?', cursor_id)
              .limit(500)
              .order(:id)

  return if batch.empty?

  batch.each { |user| process(user) }

  # Re-enqueue with cursor — job stays small, progress survives restarts
  self.class.perform_later(batch.last.id)
end
```

### Rule 3 — Explicitly release AR connections in long-running jobs

```ruby
# frozen_string_literal: true

class LongBatchJob < ApplicationJob
  def perform
    User.find_each(batch_size: 500) do |user|
      process(user)
      # Return connection to pool after each record in long jobs
      ActiveRecord::Base.connection_pool.release_connection
    end
  end

  private

  def process(user)
    # isolated work per user
  end
end
```

### Rule 4 — Never store large objects in Sidekiq job args

Sidekiq serializes args to JSON and stores them in Redis.
Large args = Redis memory pressure + slow enqueue.

```ruby
# BAD — serializes entire object graph into Redis
SomeJob.perform_later(user.to_json)
SomeJob.perform_later(large_hash_with_100_keys)

# GOOD — pass only the ID, load inside the job
SomeJob.perform_later(user.id)

# GOOD — for complex args, store in Redis with TTL and pass the key
payload_key = "job:payload:#{SecureRandom.uuid}"
redis.setex(payload_key, 1.hour.to_i, payload.to_json)
SomeJob.perform_later(payload_key)
```

### Rule 5 — Avoid closures and procs that capture scope

```ruby
# BAD — block captures surrounding scope, preventing GC
def perform(user_ids)
  processors = user_ids.map do |id|
    -> { UserProcessor.new(id).call }  # captures user_ids array in closure
  end
  processors.each(&:call)
end

# GOOD — no closures, no captured scope
def perform(user_ids)
  user_ids.each do |id|
    UserProcessor.new(id).call
  end
end
```
