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
