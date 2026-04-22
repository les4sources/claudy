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
// 'invisible opacity-0' when hidden (matches the existing `_tooltips.html.slim` partials).
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
