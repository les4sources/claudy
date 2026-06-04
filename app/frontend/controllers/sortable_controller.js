import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-drop reordering for agenda items across the four typed lists
// (Atelier, Informations, Triage, Décisions). One controller per list <ul>;
// all lists share the same SortableJS group so points can move between lists.
//
// Usage:
//   ul(data-controller="sortable"
//      data-sortable-url-value="/gatherings/12/agenda_items/reorder"
//      data-sortable-list-value="atelier")
//     li(data-sortable-target="item" data-id="7") ...
//
// On drop, sends a PATCH { ids: [...], list } for the destination list and,
// when the point came from another list, for the source list too. Each PATCH
// returns a Turbo Stream that refreshes that list's counter.
export default class extends Controller {
  static targets = ["item"]
  static values = { url: String, list: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "agenda-items",
      handle: "[data-sortable-handle]",
      draggable: "[data-sortable-target='item']",
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

  async persist(evt) {
    const lists = new Set([evt.from, evt.to])
    await Promise.all(Array.from(lists).map((listEl) => this._persistList(listEl)))
  }

  async _persistList(listEl) {
    const ids = Array.from(listEl.querySelectorAll("[data-sortable-target='item']")).map(
      (el) => el.dataset.id
    )
    const list = listEl.dataset.sortableListValue
    const url = listEl.dataset.sortableUrlValue
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrf,
      },
      body: JSON.stringify({ ids, list }),
    })

    if (response.ok) {
      const html = await response.text()
      if (html.trim() && window.Turbo) window.Turbo.renderStreamMessage(html)
    }
  }
}
