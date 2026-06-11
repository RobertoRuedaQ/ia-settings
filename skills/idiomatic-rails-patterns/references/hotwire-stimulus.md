# Hotwire — Stimulus Foundations

Stimulus best practices, timer cleanup, timing helpers, state persistence,
frame reload on document morph, cached fragment personalization, progressive
installation. For Turbo (frames/streams/morphing) see `hotwire-turbo.md`.
For specific reusable controllers (dialog/drag/hotkey/etc.) see
`hotwire-controllers.md`.

---

## Stimulus Best Practices

- Use **Values API** over `getAttribute()` - cleaner, type-coerced
- Use **camelCase** in JavaScript (even for data attributes)
- Always clean up in `disconnect()` - timers, listeners
- Use `:self` action filter to scope events
- Extract shared helpers to modules (`date_helpers.js`, `timing_helpers.js`)

### Timer Cleanup Pattern

Always clean up intervals and timeouts in `disconnect()`:

```javascript
export default class extends Controller {
  #timer

  connect() {
    this.#timer = setInterval(() => this.refresh(), 30_000)
  }

  disconnect() {
    clearInterval(this.#timer)
  }
}
```

### Timing Helpers

Extract common timing utilities to shared modules:

```javascript
// helpers/timing_helpers.js
export function throttle(fn, delay = 1000) {
  let timeoutId = null
  return (...args) => {
    if (!timeoutId) {
      fn(...args)
      timeoutId = setTimeout(() => timeoutId = null, delay)
    }
  }
}

export function debounce(fn, delay = 1000) {
  let timeoutId = null
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn.apply(this, args), delay)
  }
}

export function nextFrame() {
  return new Promise(requestAnimationFrame)
}

export function nextEvent(element, eventName) {
  return new Promise(resolve =>
    element.addEventListener(eventName, resolve, { once: true })
  )
}
```

---

## State Persistence

- localStorage for UI preferences (expanded panels, draft content)
- Accept flash-of-collapsed-content as acceptable tradeoff
- Restore state on `turbo:morph-element` events
- Use `nextFrame()` helper to wait for morph completion

### Restoring localStorage on Morph

```javascript
export default class extends Controller {
  static targets = ["input"]
  static values = { key: String }

  initialize() {
    this.save = debounce(this.save.bind(this), 300)
  }

  connect() {
    this.restoreContent()
  }

  save() {
    const content = this.inputTarget.value
    if (content) {
      localStorage.setItem(this.keyValue, content)
    } else {
      localStorage.removeItem(this.keyValue)
    }
  }

  async restoreContent() {
    await nextFrame()
    const saved = localStorage.getItem(this.keyValue)
    if (saved) {
      this.inputTarget.value = saved
    }
  }
}
```

Wire it up to restore after morphs:

```erb
<%= form.text_area :body,
      data: {
        local_save_target: "input",
        action: "input->local-save#save turbo:morph-element->local-save#restoreContent"
      } %>
```

---

## Frame Reload on Document Morph

Reload frames after document-level morphs:

```javascript
export default class extends Controller {
  reload() {
    this.element.reload()
  }

  morphReload(event) {
    const newElement = event.detail.newElement
    if (newElement?.tagName === "TURBO-FRAME") {
      event.preventDefault()
      this.element.reload()
    }
  }
}
```

```erb
<%= turbo_frame_tag "dynamic-content",
      src: content_path,
      data: {
        controller: "frame",
        action: "turbo:morph@document->frame#reload"
      } %>
```

---

## Stimulus for Cached Fragment Personalization

Cached partials can't access `Current.user`. Move user-specific styling to client-side:

```javascript
// initializers/current.js
class Current {
  get user() {
    const id = document.head.querySelector('meta[name="current-user-id"]')?.content
    return id ? { id: parseInt(id) } : null
  }
}
window.Current = new Current()
```

```javascript
// controllers/personalize_controller.js
export default class extends Controller {
  static targets = ["item"]
  static classes = ["mine"]

  itemTargetConnected(element) {
    if (element.dataset.creatorId == Current.user?.id) {
      element.classList.add(this.mineClass)
    }
  }
}
```

```erb
<!-- In layout -->
<meta name="current-user-id" content="<%= Current.user&.id %>">

<!-- Cached partial uses data attributes, not conditionals -->
<div data-creator-id="<%= comment.creator_id %>"
     data-personalize-target="item">
```

---

## Progressive Installation

Show interactive UI only after JavaScript loads:

```javascript
connect() {
  this.element.classList.add("installed")
}
```

```css
.interactive-widget {
  visibility: hidden;
}

.interactive-widget.installed {
  visibility: visible;
}
```

Also restore after morphs:

```erb
data-action="turbo:morph@document->widget#install"
```

---

## Using @rails/request.js with Turbo

Make `@rails/request.js` use Turbo's fetch for proper integration:

```javascript
// application.js
window.fetch = Turbo.fetch
```
