# Remove Flowbite JS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the memory/listener leak caused by `flowbite/dist/flowbite.turbo.js` by replacing Flowbite's dropdown/collapse/tooltip/popover runtime with four Stimulus controllers that clean up on `disconnect()`.

**Architecture:** Four custom Stimulus controllers (`dropdown`, `collapse`, `tooltip`, `popover`) live in `app/frontend/controllers/` and are auto-registered by the existing `stimulus-vite-helpers` glob in `app/frontend/utils/setupStimulus.js`. Each uses Stimulus `values` API and `data-action` wiring so listeners are removed automatically when Turbo replaces the `<body>`. Popper.js (already in `node_modules/@popperjs/core` as a Flowbite transitive dep) handles positioning for tooltips and popovers. The Flowbite datepicker import is kept — it's a separate entry point not involved in the leak.

**Tech Stack:** Rails 7 + Slim, Vite + Hotwire (Turbo 7.2, Stimulus 3.2), `@popperjs/core`.

---

## File Structure

**Create:**
- `app/frontend/controllers/dropdown_controller.js` — toggle an element referenced by id, close on outside click.
- `app/frontend/controllers/collapse_controller.js` — toggle an element referenced by id (mobile menu).
- `app/frontend/controllers/tooltip_controller.js` — show/hide a referenced tooltip on hover/focus, positioned by Popper.
- `app/frontend/controllers/popover_controller.js` — show/hide a referenced popover on click (or hover), positioned by Popper, close on outside click.

**Modify (JS):**
- `app/frontend/entrypoints/application.js` — remove `import 'flowbite'` and `import 'flowbite/dist/flowbite.turbo.js'`. Keep datepicker imports.
- `app/frontend/entrypoints/public.js` — same removals.

**Modify (views):**
- `app/views/layouts/components/_navbar.html.slim` — hamburger button (collapse) and "Accueil" button (dropdown).
- `app/views/pages/calendar.html.slim` — 3 popover triggers (event / space-reservation / reservation).
- `app/views/shared/_popover_icon.html.erb` — popover icon button.
- `app/views/human_roles/_edit.html.slim` — 3 tooltip triggers.
- `app/views/human_roles/_day.html.slim` — 1 tooltip trigger.
- `app/views/human_roles/_human_role.html.slim` — 1 tooltip trigger.

**Modify (decorators):**
- `app/decorators/booking_decorator.rb` — `room_badge` tooltip trigger (line ~336) and `status_icon` tooltip triggers (lines ~363-369).
- `app/decorators/space_booking_decorator.rb` — `space_badge` tooltip trigger (line ~213) and `status_icon` tooltip triggers (lines ~240-246).

**Unchanged:**
- The `#tooltip-*` and `#popover-*` target divs themselves — their markup stays as is, only the trigger side is migrated.
- `app/frontend/controllers/application.js` and `setupStimulus.js` — the glob auto-registers new controllers.

---

### Task 1: Add `@popperjs/core` as a direct dependency

**Why:** It currently resolves as a transitive dep via flowbite. A future flowbite removal would break imports. Make it explicit now to decouple.

**Files:**
- Modify: `package.json`
- Modify: `yarn.lock`

- [ ] **Step 1: Add the dependency**

Run: `yarn add @popperjs/core@^2.11.0`

Expected: `package.json` gets `"@popperjs/core": "^2.11.8"` (or similar 2.11.x) in `dependencies`, `yarn.lock` is updated.

- [ ] **Step 2: Verify Vite can resolve the import**

Run:
```bash
node -e "console.log(require.resolve('@popperjs/core'))"
```

Expected: path ending in `node_modules/@popperjs/core/lib/index.js` (or similar).

- [ ] **Step 3: Commit**

```bash
git add package.json yarn.lock
git commit -m "Add @popperjs/core as a direct dependency"
```

---

### Task 2: Create `dropdown_controller.js`

**Files:**
- Create: `app/frontend/controllers/dropdown_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/frontend/controllers/dropdown_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus"

// Replaces Flowbite `data-dropdown-toggle`.
// Usage:
//   button(data-controller="dropdown"
//          data-action="click->dropdown#toggle click@window->dropdown#hideOnClickOutside"
//          data-dropdown-toggle-value="menuId")
export default class extends Controller {
  static values = { toggle: String }

  connect() {
    this.menuEl = document.getElementById(this.toggleValue)
  }

  disconnect() {
    this.menuEl = null
  }

  toggle(event) {
    event.preventDefault()
    if (!this.menuEl) return
    this.menuEl.classList.toggle("hidden")
    const expanded = !this.menuEl.classList.contains("hidden")
    this.element.setAttribute("aria-expanded", expanded ? "true" : "false")
  }

  hideOnClickOutside(event) {
    if (!this.menuEl || this.menuEl.classList.contains("hidden")) return
    if (this.element.contains(event.target)) return
    if (this.menuEl.contains(event.target)) return
    this.menuEl.classList.add("hidden")
    this.element.setAttribute("aria-expanded", "false")
  }
}
```

- [ ] **Step 2: Verify Vite picks it up**

Run: `grep -l "dropdown_controller" app/frontend/controllers/`

Expected: `app/frontend/controllers/dropdown_controller.js`.

No build verification yet — the controller only activates once we migrate the HTML trigger in Task 6.

- [ ] **Step 3: Commit**

```bash
git add app/frontend/controllers/dropdown_controller.js
git commit -m "Add dropdown Stimulus controller to replace Flowbite dropdown"
```

---

### Task 3: Create `collapse_controller.js`

**Files:**
- Create: `app/frontend/controllers/collapse_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/frontend/controllers/collapse_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus"

// Replaces Flowbite `data-collapse-toggle`.
// Usage:
//   button(data-controller="collapse"
//          data-action="click->collapse#toggle"
//          data-collapse-toggle-value="targetId")
export default class extends Controller {
  static values = { toggle: String }

  connect() {
    this.targetEl = document.getElementById(this.toggleValue)
  }

  disconnect() {
    this.targetEl = null
  }

  toggle(event) {
    event.preventDefault()
    if (!this.targetEl) return
    this.targetEl.classList.toggle("hidden")
    const expanded = !this.targetEl.classList.contains("hidden")
    this.element.setAttribute("aria-expanded", expanded ? "true" : "false")
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/frontend/controllers/collapse_controller.js
git commit -m "Add collapse Stimulus controller to replace Flowbite collapse"
```

---

### Task 4: Create `tooltip_controller.js`

**Files:**
- Create: `app/frontend/controllers/tooltip_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/frontend/controllers/tooltip_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

// Replaces Flowbite `data-tooltip-target`.
// Usage:
//   el(data-controller="tooltip"
//      data-action="mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide"
//      data-tooltip-target-value="tooltip-human-42"
//      data-tooltip-placement-value="top")
//
// The tooltip element (by id) is expected to carry Tailwind classes
// 'invisible opacity-0' when hidden and to have a '.tooltip-arrow' child
// with `data-popper-arrow` for positioning (matches the existing
// `_tooltips.html.slim` partials' markup).
export default class extends Controller {
  static values = {
    target: String,
    placement: { type: String, default: "top" },
  }

  connect() {
    this.tooltipEl = document.getElementById(this.targetValue)
    this.popper = null
  }

  disconnect() {
    this.hide()
    this.tooltipEl = null
  }

  show() {
    if (!this.tooltipEl) return
    if (!this.popper) {
      this.popper = createPopper(this.element, this.tooltipEl, {
        placement: this.placementValue,
        modifiers: [{ name: "offset", options: { offset: [0, 8] } }],
      })
    } else {
      this.popper.update()
    }
    this.tooltipEl.classList.remove("invisible", "opacity-0")
    this.tooltipEl.classList.add("visible", "opacity-100")
  }

  hide() {
    if (!this.tooltipEl) return
    this.tooltipEl.classList.remove("visible", "opacity-100")
    this.tooltipEl.classList.add("invisible", "opacity-0")
    if (this.popper) {
      this.popper.destroy()
      this.popper = null
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/frontend/controllers/tooltip_controller.js
git commit -m "Add tooltip Stimulus controller to replace Flowbite tooltip"
```

---

### Task 5: Create `popover_controller.js`

**Files:**
- Create: `app/frontend/controllers/popover_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/frontend/controllers/popover_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus"
import { createPopper } from "@popperjs/core"

// Replaces Flowbite `data-popover-target` + `data-popover-trigger`.
// Click-trigger usage:
//   el(data-controller="popover"
//      data-action="click->popover#toggle click@window->popover#hideOnClickOutside"
//      data-popover-target-value="popover-event-12"
//      data-popover-trigger-value="click"
//      data-popover-placement-value="top")
//
// Hover-trigger usage:
//   el(data-controller="popover"
//      data-action="mouseenter->popover#show mouseleave->popover#hide"
//      data-popover-target-value="popover-tier-soutien"
//      data-popover-trigger-value="hover"
//      data-popover-placement-value="top")
export default class extends Controller {
  static values = {
    target: String,
    trigger: { type: String, default: "click" },
    placement: { type: String, default: "top" },
  }

  connect() {
    this.popoverEl = document.getElementById(this.targetValue)
    this.popper = null
    this.visible = false
  }

  disconnect() {
    this._hide()
    this.popoverEl = null
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.visible) {
      this._hide()
    } else {
      this._show()
    }
  }

  show() {
    this._show()
  }

  hide() {
    this._hide()
  }

  hideOnClickOutside(event) {
    if (!this.visible) return
    if (this.element.contains(event.target)) return
    if (this.popoverEl && this.popoverEl.contains(event.target)) return
    this._hide()
  }

  _show() {
    if (!this.popoverEl || this.visible) return
    if (!this.popper) {
      this.popper = createPopper(this.element, this.popoverEl, {
        placement: this.placementValue,
        modifiers: [{ name: "offset", options: { offset: [0, 8] } }],
      })
    } else {
      this.popper.update()
    }
    this.popoverEl.classList.remove("invisible", "opacity-0")
    this.popoverEl.classList.add("visible", "opacity-100")
    this.visible = true
  }

  _hide() {
    if (!this.popoverEl) return
    this.popoverEl.classList.remove("visible", "opacity-100")
    this.popoverEl.classList.add("invisible", "opacity-0")
    this.visible = false
    if (this.popper) {
      this.popper.destroy()
      this.popper = null
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/frontend/controllers/popover_controller.js
git commit -m "Add popover Stimulus controller to replace Flowbite popover"
```

---

### Task 6: Migrate the navbar

**Files:**
- Modify: `app/views/layouts/components/_navbar.html.slim`

- [ ] **Step 1: Migrate the hamburger (collapse) button**

Current content at line 12:

```slim
button.inline-flex.items-center.p-2.w-10.h-10.justify-center.text-gray-500.rounded-lg.md:hidden.hover:bg-teal-50.focus:outline-none.focus:ring-2.focus:ring-teal-200.transition-colors[data-collapse-toggle="navbar-dropdown" type="button" aria-controls="navbar-dropdown" aria-expanded="false"]
```

Replace with:

```slim
button.inline-flex.items-center.p-2.w-10.h-10.justify-center.text-gray-500.rounded-lg.md:hidden.hover:bg-teal-50.focus:outline-none.focus:ring-2.focus:ring-teal-200.transition-colors[data-controller="collapse" data-action="click->collapse#toggle" data-collapse-toggle-value="navbar-dropdown" type="button" aria-controls="navbar-dropdown" aria-expanded="false"]
```

- [ ] **Step 2: Migrate the "Accueil" dropdown button**

Current content at line 34:

```slim
button.flex.items-center.gap-1.5.px-4.py-2.rounded-lg.text-sm.font-medium.transition-all.duration-150[id="accueilDropdownButton" data-dropdown-toggle="accueilDropdown" type="button" class="#{ (controller_name == 'bookings' || controller_name == 'space_bookings') ? 'text-4s-main bg-teal-50' : 'text-gray-600 hover:text-4s-main hover:bg-teal-50/60'}"]
```

Replace with:

```slim
button.flex.items-center.gap-1.5.px-4.py-2.rounded-lg.text-sm.font-medium.transition-all.duration-150[id="accueilDropdownButton" data-controller="dropdown" data-action="click->dropdown#toggle click@window->dropdown#hideOnClickOutside" data-dropdown-toggle-value="accueilDropdown" type="button" class="#{ (controller_name == 'bookings' || controller_name == 'space_bookings') ? 'text-4s-main bg-teal-50' : 'text-gray-600 hover:text-4s-main hover:bg-teal-50/60'}"]
```

- [ ] **Step 3: Manually verify in browser**

Run `bin/dev`. Open http://localhost:3000. In DevTools console, navigate 5 times between pages. Click the "Accueil" button — the dropdown should open; click outside — it should close. Resize to mobile (< 768px) and click the hamburger — menu should toggle.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/components/_navbar.html.slim
git commit -m "Migrate navbar dropdown and collapse to Stimulus controllers"
```

---

### Task 7: Migrate calendar popovers

**Files:**
- Modify: `app/views/pages/calendar.html.slim`

- [ ] **Step 1: Migrate the event popover trigger (line 31)**

Current:

```slim
      .absolute.top-0.left-0.w-full.h-full(data-popover-target="popover-event-#{event.id}" data-popover-trigger="click")
```

Replace with:

```slim
      .absolute.top-0.left-0.w-full.h-full(data-controller="popover" data-action="click->popover#toggle click@window->popover#hideOnClickOutside" data-popover-target-value="popover-event-#{event.id}" data-popover-trigger-value="click")
```

- [ ] **Step 2: Migrate the space-reservation popover trigger (line 61)**

Current:

```slim
        .absolute.top-0.left-0.w-full.h-full(data-popover-target="popover-space-reservation-#{space_reservation.id}" data-popover-trigger="click")
```

Replace with:

```slim
        .absolute.top-0.left-0.w-full.h-full(data-controller="popover" data-action="click->popover#toggle click@window->popover#hideOnClickOutside" data-popover-target-value="popover-space-reservation-#{space_reservation.id}" data-popover-trigger-value="click")
```

- [ ] **Step 3: Migrate the reservation popover trigger (line 90)**

Current:

```slim
        .absolute.top-0.left-0.w-full.h-full(data-popover-target="popover-reservation-#{reservation.id}" data-popover-trigger="click")
```

Replace with:

```slim
        .absolute.top-0.left-0.w-full.h-full(data-controller="popover" data-action="click->popover#toggle click@window->popover#hideOnClickOutside" data-popover-target-value="popover-reservation-#{reservation.id}" data-popover-trigger-value="click")
```

- [ ] **Step 4: Manually verify**

With `bin/dev` running, open the calendar page. Click on a reservation/event tile — its popover opens. Click another tile — the previous popover closes and the new one opens. Click empty space — the open popover closes.

- [ ] **Step 5: Commit**

```bash
git add app/views/pages/calendar.html.slim
git commit -m "Migrate calendar popovers to Stimulus controller"
```

---

### Task 8: Migrate `shared/_popover_icon.html.erb`

**Files:**
- Modify: `app/views/shared/_popover_icon.html.erb`

- [ ] **Step 1: Replace the file**

Current content:

```erb
<button data-popover-target="<%= target %>" type="button" data-popover-placement="top">
	<svg class="w-5 h-5 inline-block align-middle text-gray-400 hover:text-gray-500" aria-hidden="true" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
		<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"></path>
	</svg>
	<span class="sr-only">En savoir plus</span>
</button>
```

Replace with:

```erb
<button data-controller="popover" data-action="mouseenter->popover#show mouseleave->popover#hide focus->popover#show blur->popover#hide" data-popover-target-value="<%= target %>" data-popover-trigger-value="hover" data-popover-placement-value="top" type="button">
	<svg class="w-5 h-5 inline-block align-middle text-gray-400 hover:text-gray-500" aria-hidden="true" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
		<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"></path>
	</svg>
	<span class="sr-only">En savoir plus</span>
</button>
```

- [ ] **Step 2: Manually verify**

Open a page using this partial (e.g. space booking edit form → payment section). Hover the help icon next to "Soutien" — the tier popover should appear. Move the mouse away — it hides.

- [ ] **Step 3: Commit**

```bash
git add app/views/shared/_popover_icon.html.erb
git commit -m "Migrate shared popover_icon to Stimulus controller"
```

---

### Task 9: Migrate `human_roles` view partials

**Files:**
- Modify: `app/views/human_roles/_edit.html.slim`
- Modify: `app/views/human_roles/_day.html.slim`
- Modify: `app/views/human_roles/_human_role.html.slim`

- [ ] **Step 1: Migrate `_edit.html.slim`**

Find three occurrences of:

```
data: { "tooltip-target": "tooltip-human-#{human.id}", "keep-turbo-frame-open": true }
```

Replace each with:

```
data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-human-#{human.id}", "keep-turbo-frame-open": true }
```

(There are three `button_to` calls with the same pattern — update all three.)

- [ ] **Step 2: Migrate `_day.html.slim`**

Current (line 7):

```slim
                data: { "tooltip-target": "tooltip-human-#{human_role.human.id}" }
```

Replace with:

```slim
                data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-human-#{human_role.human.id}" }
```

- [ ] **Step 3: Migrate `_human_role.html.slim`**

Current (line 1):

```slim
= tag.div class: "text-xs", data: { "tooltip-target": "tooltip-human-#{human_role.human.id}" } do
```

Replace with:

```slim
= tag.div class: "text-xs", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-human-#{human_role.human.id}" } do
```

- [ ] **Step 4: Manually verify**

Open the organisation page with the human-roles grid. Hover a human avatar — the name tooltip should appear. Move mouse away — it disappears.

- [ ] **Step 5: Commit**

```bash
git add app/views/human_roles/
git commit -m "Migrate human_roles tooltip triggers to Stimulus controller"
```

---

### Task 10: Migrate `booking_decorator.rb`

**Files:**
- Modify: `app/decorators/booking_decorator.rb`

- [ ] **Step 1: Read current state**

Run: `grep -n "tooltip-target" app/decorators/booking_decorator.rb`

Expected output (line numbers may vary slightly):

```
336:        "data-tooltip-target": "tooltip-room-#{room.id}"
363:      h.content_tag(:span, "❌", data: { "tooltip-target": "tooltip-status-canceled" })
365:      h.content_tag(:span, "✅", data: { "tooltip-target": "tooltip-status-confirmed" })
367:      h.content_tag(:span, "⏳", data: { "tooltip-target": "tooltip-status-pending" })
369:      h.content_tag(:span, "🙅‍♀️", data: { "tooltip-target": "tooltip-status-declined" })
```

- [ ] **Step 2: Migrate the `room_badge` tooltip**

Around line 336, the surrounding code attaches the tooltip target to a badge. Replace the single-key hash entry:

```ruby
"data-tooltip-target": "tooltip-room-#{room.id}"
```

with the three keys required by the Stimulus controller. The badge is built via `h.content_tag` or equivalent — open the method around line 330-340 and update the `data:` hash so it includes:

```ruby
controller: "tooltip",
action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide",
"tooltip-target-value": "tooltip-room-#{room.id}"
```

Read the method first to integrate correctly into its existing hash literal.

- [ ] **Step 3: Migrate the four `status_icon` tooltips**

Replace each of the four lines (around 363-369):

```ruby
h.content_tag(:span, "❌", data: { "tooltip-target": "tooltip-status-canceled" })
h.content_tag(:span, "✅", data: { "tooltip-target": "tooltip-status-confirmed" })
h.content_tag(:span, "⏳", data: { "tooltip-target": "tooltip-status-pending" })
h.content_tag(:span, "🙅‍♀️", data: { "tooltip-target": "tooltip-status-declined" })
```

with:

```ruby
h.content_tag(:span, "❌", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-canceled" })
h.content_tag(:span, "✅", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-confirmed" })
h.content_tag(:span, "⏳", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-pending" })
h.content_tag(:span, "🙅‍♀️", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-declined" })
```

- [ ] **Step 4: Verify no more old references in this file**

Run: `grep -n '"tooltip-target":' app/decorators/booking_decorator.rb`

Expected: no matches.

- [ ] **Step 5: Manually verify**

Open the calendar page. Inside a reservation tile popover, the room badges and the status emoji should render. Hover a room badge — the room tooltip appears. Hover the status emoji — the status tooltip appears.

- [ ] **Step 6: Commit**

```bash
git add app/decorators/booking_decorator.rb
git commit -m "Migrate booking_decorator tooltip triggers to Stimulus controller"
```

---

### Task 11: Migrate `space_booking_decorator.rb`

**Files:**
- Modify: `app/decorators/space_booking_decorator.rb`

- [ ] **Step 1: Migrate the `space_badge` tooltip (around line 213)**

Replace:

```ruby
"data-tooltip-target": "tooltip-space-#{space.id}"
```

with (integrated into the surrounding `data:` hash of the badge):

```ruby
controller: "tooltip",
action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide",
"tooltip-target-value": "tooltip-space-#{space.id}"
```

Read the method first (around lines 205-220) to merge into its existing data hash.

- [ ] **Step 2: Migrate the four status_icon tooltips (lines ~240-246)**

Replace each of:

```ruby
h.content_tag(:span, "❌", data: { "tooltip-target": "tooltip-status-canceled" })
h.content_tag(:span, "✅", data: { "tooltip-target": "tooltip-status-confirmed" })
h.content_tag(:span, "⏳", data: { "tooltip-target": "tooltip-status-pending" })
h.content_tag(:span, "🙅‍♀️", data: { "tooltip-target": "tooltip-status-declined" })
```

with:

```ruby
h.content_tag(:span, "❌", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-canceled" })
h.content_tag(:span, "✅", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-confirmed" })
h.content_tag(:span, "⏳", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-pending" })
h.content_tag(:span, "🙅‍♀️", data: { controller: "tooltip", action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide", "tooltip-target-value": "tooltip-status-declined" })
```

- [ ] **Step 3: Verify no more old references**

Run: `grep -n '"tooltip-target":' app/decorators/space_booking_decorator.rb`

Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add app/decorators/space_booking_decorator.rb
git commit -m "Migrate space_booking_decorator tooltip triggers to Stimulus controller"
```

---

### Task 12: Remove Flowbite JS imports

**Files:**
- Modify: `app/frontend/entrypoints/application.js`
- Modify: `app/frontend/entrypoints/public.js`

- [ ] **Step 1: Edit `application.js`**

Remove the `import 'flowbite';` line (currently line 31) and the `import 'flowbite/dist/flowbite.turbo.js';` line (currently line 34). Keep the datepicker imports.

Expected resulting content for the flowbite-related block:

```js
import 'flowbite/dist/datepicker';
import '../utils/datepicker.turbo.min.js';
```

(i.e. only the two datepicker-related imports remain.)

- [ ] **Step 2: Edit `public.js`**

Same removals. Read the file first:

```bash
cat app/frontend/entrypoints/public.js
```

Remove only `import 'flowbite';` and `import 'flowbite/dist/flowbite.turbo.js';` if present. Keep everything else. If `public.js` only imports `flowbite` (no `.turbo.js`), still remove it since we no longer rely on any flowbite runtime JS.

- [ ] **Step 3: Verify no other app file imports flowbite runtime**

Run:

```bash
grep -rn "import 'flowbite'\|import \"flowbite\"\|flowbite.turbo" app/frontend
```

Expected: no results except possibly `flowbite/dist/datepicker` or `datepicker.turbo.min.js` (both fine).

- [ ] **Step 4: Verify dev server boots and the app renders**

Run: `bin/dev`

Open http://localhost:3000. No console errors. The navbar, calendar popovers, tooltips, and datepicker all work.

- [ ] **Step 5: Commit**

```bash
git add app/frontend/entrypoints/application.js app/frontend/entrypoints/public.js
git commit -m "Remove Flowbite runtime JS imports to stop listener leak"
```

---

### Task 13: Manual performance verification

**No file changes** — this task produces evidence that the leak is fixed.

- [ ] **Step 1: Start dev server**

Run: `bin/dev`

- [ ] **Step 2: Baseline listener count**

Open http://localhost:3000 in Chrome. Open DevTools → Console. Run:

```js
getEventListeners(document.body).click?.length ?? 0
```

Record the number (e.g. `3`).

- [ ] **Step 3: Navigate 15 times**

Click through: Calendar → Hébergements → Organisation → Reporting → Comptabilité → Calendar → repeat three cycles (~15 navigations). Each navigation should feel fast.

- [ ] **Step 4: Re-check listener count**

Run the same snippet again. The count should be the same or within ±1-2 of the baseline (not growing with the number of navigations).

- [ ] **Step 5: Functional smoke test**

Verify on the browser (no commit):
- Calendar: click a reservation tile → popover opens. Click elsewhere → closes.
- Navbar "Accueil" → dropdown opens/closes.
- Mobile viewport → hamburger menu toggles.
- Organisation → hover on human avatar → tooltip appears.
- Booking form → datepicker opens when clicking the date input.

- [ ] **Step 6: If all checks pass, create a summary commit message for the PR**

No commit needed — this task is verification only. Just note the before/after listener counts in the PR description.

---

## Self-Review

- [x] **Spec coverage:**
  - Dropdown migration → Task 2, Task 6.
  - Collapse migration → Task 3, Task 6.
  - Tooltip migration → Task 4, Task 9, Task 10, Task 11.
  - Popover migration → Task 5, Task 7, Task 8.
  - Remove Flowbite JS imports → Task 12.
  - Verify no leak → Task 13.
  - Add explicit `@popperjs/core` dep (beyond spec but required to decouple cleanly) → Task 1.
- [x] **No placeholders:** every code block is concrete.
- [x] **Type consistency:** `data-X-target-value` / `data-X-toggle-value` are used consistently. `createPopper` signature matches `@popperjs/core` API.
