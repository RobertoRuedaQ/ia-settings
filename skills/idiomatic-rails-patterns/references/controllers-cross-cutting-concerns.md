# Controllers — Cross-Cutting Concerns

Request-context concerns (CurrentRequest, CurrentTimezone, SetPlatform),
security/header concerns (BlockSearchEngineIndexing, RequestForgeryProtection),
and Turbo/view concerns (TurboFlash, ViewTransitions).

For basics (thin-controllers principle, ApplicationController, authorization)
see `controllers-basics.md`. For resource-scoping and filtering concerns see
`controllers-resource-concerns.md`.

---

## Request Context Concerns

### CurrentRequest — Populate Current with Request Data

```ruby
# app/controllers/concerns/current_request.rb
module CurrentRequest
  extend ActiveSupport::Concern

  included do
    before_action do
      Current.http_method = request.method
      Current.request_id  = request.uuid
      Current.user_agent  = request.user_agent
      Current.ip_address  = request.ip
      Current.referrer    = request.referrer
    end
  end
end
```

**Why this matters:** Models and jobs can access request context via `Current` without parameter passing:

```ruby
class Signup
  def create_identity
    Identity.create!(
      email_address: email_address,
      # These come from Current, not parameters!
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
end
```

### CurrentTimezone — User Timezone from Cookie

```ruby
# app/controllers/concerns/current_timezone.rb
module CurrentTimezone
  extend ActiveSupport::Concern

  included do
    around_action :set_current_timezone
    helper_method :timezone_from_cookie
    etag { timezone_from_cookie }
  end

  private
    def set_current_timezone(&)
      Time.use_zone(timezone_from_cookie, &)
    end

    def timezone_from_cookie
      @timezone_from_cookie ||= begin
        timezone = cookies[:timezone]
        ActiveSupport::TimeZone[timezone] if timezone.present?
      end
    end
end
```

**Key patterns:**
1. `around_action` wraps the entire request in the user's timezone
2. `etag` includes timezone - different timezones get different cached responses
3. `helper_method` makes it available in views
4. Cookie is set client-side by JavaScript detecting the user's timezone

### SetPlatform — Detect Mobile/Desktop

```ruby
# app/controllers/concerns/set_platform.rb
module SetPlatform
  extend ActiveSupport::Concern

  included do
    helper_method :platform
  end

  private
    def platform
      @platform ||= ApplicationPlatform.new(request.user_agent)
    end
end
```

**Usage in views:**

```erb
<% if platform.mobile? %>
  <%= render "mobile_nav" %>
<% else %>
  <%= render "desktop_nav" %>
<% end %>
```

---

## Security & Headers Concerns

### BlockSearchEngineIndexing — Prevent Crawling

```ruby
# app/controllers/concerns/block_search_engine_indexing.rb
module BlockSearchEngineIndexing
  extend ActiveSupport::Concern

  included do
    after_action :block_search_engine_indexing
  end

  private
    def block_search_engine_indexing
      headers["X-Robots-Tag"] = "none"
    end
end
```

**Why:** Private app content shouldn't appear in search results.

### RequestForgeryProtection — Modern CSRF

```ruby
# app/controllers/concerns/request_forgery_protection.rb
module RequestForgeryProtection
  extend ActiveSupport::Concern

  included do
    after_action :append_sec_fetch_site_to_vary_header
  end

  private
    def append_sec_fetch_site_to_vary_header
      vary_header = response.headers["Vary"].to_s.split(",").map(&:strip).reject(&:blank?)
      response.headers["Vary"] = (vary_header + ["Sec-Fetch-Site"]).join(",")
    end

    def verified_request?
      request.get? || request.head? || !protect_against_forgery? ||
        (valid_request_origin? && safe_fetch_site?)
    end

    SAFE_FETCH_SITES = %w[same-origin same-site]

    def safe_fetch_site?
      SAFE_FETCH_SITES.include?(sec_fetch_site_value) ||
        (sec_fetch_site_value.nil? && api_request?)
    end

    def api_request?
      request.format.json?
    end
end
```

**Modern approach:** Uses `Sec-Fetch-Site` header instead of tokens. Browsers set this automatically.

---

## Turbo/View Concerns

### TurboFlash — Flash Messages via Turbo Stream

```ruby
# app/controllers/concerns/turbo_flash.rb
module TurboFlash
  extend ActiveSupport::Concern

  included do
    helper_method :turbo_stream_flash
  end

  private
    def turbo_stream_flash(**flash_options)
      turbo_stream.replace(:flash, partial: "layouts/shared/flash", locals: { flash: flash_options })
    end
end
```

**Usage in controller:**

```ruby
def create
  @comment = @card.comments.create!(comment_params)

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: [
        turbo_stream.append(:comments, @comment),
        turbo_stream_flash(notice: "Comment added!")
      ]
    end
  end
end
```

### ViewTransitions — Disable on Refresh

```ruby
# app/controllers/concerns/view_transitions.rb
module ViewTransitions
  extend ActiveSupport::Concern

  included do
    before_action :disable_view_transitions, if: :page_refresh?
  end

  private
    def disable_view_transitions
      @disable_view_transition = true
    end

    def page_refresh?
      request.referrer.present? && request.referrer == request.url
    end
end
```

**Why:** View transitions on page refresh look weird. This disables them automatically.
