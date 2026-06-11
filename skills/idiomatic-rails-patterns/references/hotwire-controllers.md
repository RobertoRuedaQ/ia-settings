# Hotwire — Reusable Stimulus Controllers

Specific reusable Stimulus controllers: dialog, clipboard, hotkey, navigable
list, auto-submit, auto-save, lazy-load, drag-and-drop. For Turbo see
`hotwire-turbo.md`. For Stimulus best practices and foundations see
`hotwire-stimulus.md`.

---

## Auto-Submit Forms

Submit forms automatically on connect (useful for redirects/searches):

```javascript
export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:submit-end",
      this.#handleSubmitEnd.bind(this), { once: true })
    this.submit()
  }

  submit() {
    this.element.setAttribute("aria-busy", "true")
    this.element.requestSubmit()
  }

  #handleSubmitEnd(event) {
    if (event.detail.success) {
      this.element.remove()
    } else {
      this.element.setAttribute("aria-busy", "false")
    }
  }
}
```

## Auto-Save Forms

Save forms automatically after changes with debouncing:

```javascript
const AUTOSAVE_INTERVAL = 3000

export default class extends Controller {
  #timer

  disconnect() {
    this.submit()
  }

  async submit() {
    if (this.#dirty) {
      await this.#save()
    }
  }

  change(event) {
    if (event.target.form === this.element && !this.#dirty) {
      this.#scheduleSave()
    }
  }

  #scheduleSave() {
    this.#timer = setTimeout(() => this.#save(), AUTOSAVE_INTERVAL)
  }

  async #save() {
    clearTimeout(this.#timer)
    this.#timer = null
    this.element.requestSubmit()
  }

  get #dirty() {
    return !!this.#timer
  }
}
```

## Lazy Loading on Visibility

Fetch content when element becomes visible:

```javascript
export default class extends Controller {
  static values = { url: String }

  connect() {
    const observer = new IntersectionObserver((entries) => {
      if (entries.some(entry => entry.isIntersecting)) {
        this.#fetch()
        observer.disconnect()
      }
    })
    observer.observe(this.element)
  }

  #fetch() {
    get(this.urlValue, { responseKind: "turbo-stream" })
  }
}
```

## Dialog Controller Pattern

Handle dialogs with proper accessibility and lazy-loading:

```javascript
export default class extends Controller {
  static targets = ["dialog"]
  static values = { modal: { type: Boolean, default: false } }

  connect() {
    this.dialogTarget.setAttribute("aria-hidden", "true")
  }

  open() {
    if (this.modalValue) {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.show()
    }
    this.loadLazyFrames()
    this.dialogTarget.setAttribute("aria-hidden", "false")
  }

  close() {
    this.dialogTarget.close()
    this.dialogTarget.setAttribute("aria-hidden", "true")
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  // Prevent morphing from closing open dialogs
  preventCloseOnMorphing(event) {
    if (event.detail?.attributeName === "open") {
      event.preventDefault()
    }
  }

  loadLazyFrames() {
    this.dialogTarget.querySelectorAll("turbo-frame").forEach(frame => {
      frame.loading = "eager"
    })
  }
}
```

## Copy to Clipboard

Simple clipboard pattern with success feedback:

```javascript
export default class extends Controller {
  static values = { content: String }
  static classes = ["success"]

  async copy(event) {
    event.preventDefault()
    this.element.classList.remove(this.successClass)
    this.element.offsetWidth // Force reflow for animation reset

    try {
      await navigator.clipboard.writeText(this.contentValue)
      this.element.classList.add(this.successClass)
    } catch {}
  }
}
```

## Hotkey Controller

Handle keyboard shortcuts:

```javascript
export default class extends Controller {
  click(event) {
    if (this.#isClickable && !this.#shouldIgnore(event)) {
      event.preventDefault()
      this.element.click()
    }
  }

  #shouldIgnore(event) {
    return event.defaultPrevented ||
           event.target.closest("input, textarea, [contenteditable]")
  }

  get #isClickable() {
    return getComputedStyle(this.element).pointerEvents !== "none"
  }
}
```

Usage:

```erb
<button data-controller="hotkey"
        data-action="keydown.n@document->hotkey#click">
  New Item <kbd>N</kbd>
</button>
```

## Navigable List Pattern

Keyboard-navigable lists with arrow key support:

```javascript
export default class extends Controller {
  static targets = ["item"]
  static values = {
    selectionAttribute: { type: String, default: "aria-selected" },
    actionableItems: { type: Boolean, default: false }
  }

  connect() {
    this.selectFirst()
  }

  navigate(event) {
    switch (event.key) {
      case "ArrowDown": this.#selectNext(); break
      case "ArrowUp": this.#selectPrevious(); break
      case "Enter": this.#activateCurrent(event); break
    }
  }

  selectFirst() {
    this.#selectItem(this.#visibleItems[0])
  }

  #selectItem(item) {
    if (!item) return
    this.#clearSelection()
    item.setAttribute(this.selectionAttributeValue, "true")
    item.scrollIntoView({ block: "nearest" })
    this.currentItem = item
  }

  #clearSelection() {
    this.itemTargets.forEach(item =>
      item.removeAttribute(this.selectionAttributeValue))
  }

  get #visibleItems() {
    return this.itemTargets.filter(item => !item.hidden)
  }

  #selectNext() {
    const index = this.#visibleItems.indexOf(this.currentItem)
    if (index < this.#visibleItems.length - 1) {
      this.#selectItem(this.#visibleItems[index + 1])
    }
  }

  #selectPrevious() {
    const index = this.#visibleItems.indexOf(this.currentItem)
    if (index > 0) {
      this.#selectItem(this.#visibleItems[index - 1])
    }
  }

  #activateCurrent(event) {
    if (this.actionableItemsValue && this.currentItem) {
      const clickable = this.currentItem.querySelector("a,button")
      clickable?.click()
      event.preventDefault()
    }
  }
}
```

## Drag and Drop Patterns

### Simple Drag Controller

For basic D&D between containers, use a focused controller instead of heavyweight sortable libraries:

```javascript
export default class extends Controller {
  static targets = ["item", "container"]
  static values = { url: String }
  static classes = ["draggedItem", "hoverContainer"]

  async dragStart(event) {
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.dropEffect = "move"

    await nextFrame() // Wait for drag to start
    this.dragItem = event.target.closest("[data-drag-target='item']")
    this.sourceContainer = this.dragItem.closest("[data-drag-target='container']")
    this.dragItem.classList.add(this.draggedItemClass)
  }

  dragOver(event) {
    event.preventDefault()
    const container = event.target.closest("[data-drag-target='container']")
    this.#clearContainerHoverClasses()

    if (container && container !== this.sourceContainer) {
      container.classList.add(this.hoverContainerClass)
    }
  }

  async drop(event) {
    const container = event.target.closest("[data-drag-target='container']")
    if (!container || container === this.sourceContainer) return

    this.wasDropped = true
    // POST to server, let it re-render the column
    await post(this.urlValue, {
      body: JSON.stringify({
        item_id: this.dragItem.dataset.id,
        target: container.dataset.column
      })
    })
  }

  dragEnd() {
    this.dragItem.classList.remove(this.draggedItemClass)
    this.#clearContainerHoverClasses()
    if (this.wasDropped) this.dragItem.remove()
    this.sourceContainer = null
    this.dragItem = null
    this.wasDropped = false
  }

  #clearContainerHoverClasses() {
    this.containerTargets.forEach(c =>
      c.classList.remove(this.hoverContainerClass))
  }
}
```

**Key insights:**
- Use `await nextFrame()` before applying drag classes (prevents visual glitches)
- Track source container to prevent dropping on self
- Optimistically remove on successful drop
- Let the server handle ordering logic and re-render

### Drag Visual Feedback

```css
.drag--dragged-item {
  filter: grayscale(1) brightness(0.97);
  opacity: 0.6;
  outline: 2px dashed var(--color-accent);
}

.drag--hover-container {
  background-color: var(--color-drop-zone);
  outline: 2px dashed var(--color-accent);
  transition: background-color 200ms;
}

/* Disable hover states during drag to prevent flicker */
ul:not(.dragging) li:hover {
  background-color: var(--hover-color);
}
```

### Conditional Draggable Items

Make draggability a render-time decision:

```erb
<%= render partial: "items/item",
           collection: @items,
           locals: { draggable: @allow_reorder } %>
```

```erb
<%# In the partial %>
<article draggable="<%= local_assigns.fetch(:draggable, false) %>"
         data-drag-target="item"
         data-id="<%= item.id %>">
```

### Accessibility for Drag Handles

```erb
<button class="drag-handle">
  <%= image_tag "drag.svg", aria: { hidden: true } %>
  <span class="visually-hidden">
    Drag to reorder
  </span>
</button>
```
