# Hotwire — Turbo Patterns

Turbo Frames, Streams, Morphing, Broadcasts, Permanent, Testing, Flash.
For Stimulus best practices and foundational client-side patterns see
`hotwire-stimulus.md`. For specific reusable controllers see
`hotwire-controllers.md`.

---

## Turbo Morphing

- Enable globally: `turbo_refreshes_with method: :morph, scroll: :preserve`
- Listen for `turbo:morph-element` to restore client-side state
- Use `data-turbo-permanent` for elements that shouldn't refresh
- Ensure unique IDs - duplicates break morphing
- Set `refresh: :morph` on frames with `src` to prevent removal during morphs ([hotwired/turbo#1452](https://github.com/hotwired/turbo/pull/1452))

## Turbo Frames

- Wrap form sections in frames to prevent reset on partial updates
- Lazy-load expensive content via frames with `loading: "lazy"`
- Use `turbo_stream.replace` instead of redirects for in-place updates
- Use `refresh: :morph` on lazy-loaded frames to prevent flicker
- Use `data-turbo-frame="_parent"` to target parent frame without knowing its ID ([hotwired/turbo#1446](https://github.com/hotwired/turbo/pull/1446))

### Nested Frame Targeting

Target parent frames without hardcoding IDs:

```html
<turbo-frame id="modal">
  <turbo-frame id="search-results">
    <!-- Component doesn't need to know parent's ID -->
    <a href="/items/123" data-turbo-frame="_parent">
      Select Item
    </a>
  </turbo-frame>
</turbo-frame>
```

## Common Turbo Issues

| Problem | Solution |
|---------|----------|
| Timers not updating after morph | Bind to `turbo:morph-element` event |
| Forms resetting on page refresh | Wrap in turbo frames |
| Pagination breaking | Ensure unique IDs |
| Flickering on replace | Use `method: :morph` |
| localStorage state lost | Restore on `turbo:morph-element` |

---

## Morphing + Turbo Streams

When replacing content containing Turbo Frames:

```ruby
render turbo_stream: turbo_stream.replace(
  [@record, :container],
  partial: "records/container",
  method: :morph  # Prevents flickering
)
```

Mark nested frames as permanent:

```erb
<%= turbo_frame_tag record, :details,
    data: { turbo_permanent: true } %>
```

## Element-Level Morph Events

Prefer element-specific events over global for better performance:

```ruby
# In helper
def local_datetime_tag(datetime, style: :time, **attributes)
  tag.time datetime: datetime.to_i,
    data: {
      local_time_target: style,
      action: "turbo:morph-element->local-time#refreshTarget"
    }
end
```

More efficient than `turbo:morph@window` because it only fires on the specific element.

## Turbo Frames Preserve Form State

Wrap independent sections in frames:

```erb
<%= turbo_frame_tag @record, :settings do %>
  <%= form_with model: @record do |form| %>
    <!-- form fields -->
  <% end %>
<% end %>
```

Respond with targeted replacement instead of redirect:

```ruby
def update
  @record.update(record_params)
  render turbo_stream: turbo_stream.replace(
    [@record, :settings],
    partial: "records/settings"
  )
end
```

## POST + Turbo Streams for UI State

For state toggles (expand/collapse, watch/unwatch), use POST not GET:

```erb
<%= link_to toggle_path, data: { turbo_method: "post" } %>
```

Controller returns stream update instead of redirect.

## Frame Morphing Configuration

Set `refresh: :morph` on frames with `src`:

```erb
<%= turbo_frame_tag "notifications",
      src: notifications_path,
      refresh: "morph" %>
```

Prevents frame removal during page morphs.

## Broadcasts with Turbo Streams

### Model-Level Broadcasts

Use `broadcasts_refreshes` for automatic updates:

```ruby
module Card::Broadcastable
  extend ActiveSupport::Concern

  included do
    broadcasts_refreshes
  end
end
```

### Subscribing to Broadcasts

```erb
<%= turbo_stream_from Current.user, :notifications %>
```

## Turbo Permanent Elements

Use `data-turbo-permanent` to preserve elements across navigations:

```erb
<!-- Footer frames that persist across page loads -->
<div id="footer_frames" data-turbo-permanent>
  <%= render "notifications/tray" %>
  <%= render "quick_actions/bar" %>
</div>

<!-- Rich text editor content during morphs -->
<div class="editor-content" data-turbo-permanent>
  <%= form.rich_text_area :body %>
</div>
```

## Testing Turbo Frames

Use the built-in assertion helpers ([hotwired/turbo-rails#742](https://github.com/hotwired/turbo-rails/pull/742)):

```ruby
# Assert frame exists with specific attributes
assert_turbo_frame "comments", loading: "lazy"
assert_turbo_frame @user, :profile, target: "_top"

# Assert frame contains specific content
assert_turbo_frame "search-results" do
  assert_select "li", count: 5
end

# Assert frame doesn't exist
assert_no_turbo_frame "admin-panel"
```

## Turbo Flash Helper

Create a helper for flash messages in Turbo Stream responses:

```ruby
module TurboFlash
  extend ActiveSupport::Concern

  included do
    helper_method :turbo_stream_flash
  end

  private
    def turbo_stream_flash(**flash_options)
      turbo_stream.replace(:flash,
        partial: "layouts/shared/flash",
        locals: { flash: flash_options })
    end
end
```

Usage in controller:

```ruby
def create
  @record = Record.create!(record_params)
  render turbo_stream: [
    turbo_stream.prepend("records", @record),
    turbo_stream_flash(notice: "Created successfully")
  ]
end
```

## Links Over JavaScript

- Filter chips as plain `<a>` tags, not JS-powered buttons
- Better browser affordances (right-click, cmd+click)
- Simpler, more declarative code
- Let the browser do what browsers do
