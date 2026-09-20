import { Controller } from "@hotwired/stimulus"

// Replaces Flowbite `data-dropdown-toggle`.
// Usage:
//   button(data-controller="dropdown"
//          data-action="click->dropdown#toggle click@window->dropdown#hideOnClickOutside"
//          data-dropdown-toggle-value="menuId")
//
// Ajouter `keydown.esc@window->dropdown#hide` referme au clavier — utile dès
// qu'un menu couvre du contenu, comme dans la sous-navigation Comptabilité.
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
    // Deux menus ouverts côte à côte se recouvrent : ouvrir celui-ci ferme les
    // autres. L'événement est écouté par toutes les instances, y compris celles
    // d'autres barres — elles ne réagissent que si le menu leur appartient.
    if (this.menuEl.classList.contains("hidden")) {
      window.dispatchEvent(new CustomEvent("dropdown:open", { detail: { id: this.toggleValue } }))
    }
    this.menuEl.classList.toggle("hidden")
    this.element.setAttribute("aria-expanded", this.expanded ? "true" : "false")
  }

  hide() {
    if (!this.menuEl || this.menuEl.classList.contains("hidden")) return
    this.menuEl.classList.add("hidden")
    this.element.setAttribute("aria-expanded", "false")
  }

  // Un autre menu vient de s'ouvrir : on se referme, sauf si c'est le nôtre.
  hideOnOtherOpen(event) {
    if (event.detail?.id === this.toggleValue) return
    this.hide()
  }

  hideOnClickOutside(event) {
    if (!this.menuEl || this.menuEl.classList.contains("hidden")) return
    if (this.element.contains(event.target)) return
    if (this.menuEl.contains(event.target)) return
    this.hide()
  }

  get expanded() {
    return !this.menuEl.classList.contains("hidden")
  }
}
