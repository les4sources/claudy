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
