import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-drop reordering for agenda items.
//
// Usage:
//   ul(data-controller="sortable"
//      data-sortable-url-value="/gatherings/12/agenda_items/reorder")
//     li(data-sortable-target="item" data-id="7")
//       button(data-sortable-handle) ⋮⋮
//       ...
//
// On drop, sends a PATCH with { ids: [...] } in the new order.
export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: "[data-sortable-handle]",
      animation: 150,
      ghostClass: "opacity-40",
      chosenClass: "ring-2",
      onEnd: this.persist.bind(this),
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }

  async persist() {
    const ids = this.itemTargets.map(el => el.dataset.id)
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrf,
      },
      body: JSON.stringify({ ids }),
    })
  }
}
