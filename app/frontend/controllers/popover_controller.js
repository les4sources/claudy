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
