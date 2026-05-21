import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-drop sortable for cycle actions.
//
// One controller per category list. All lists share the same group so items
// can move between categories. Sends a PATCH /cycle_actions/reorder per
// affected list (source and destination) with the new id order.
export default class extends Controller {
  static targets = ["item"]
  static values = {
    url: String,
    category: String,
    humanId: Number,
  }

  connect() {
    this.element.setAttribute("data-cycle-action-sortable-target", "list")
    this.sortable = Sortable.create(this.element, {
      group: "cycle-actions",
      handle: "[data-drag-handle]",
      draggable: "[data-cycle-action-sortable-target='item']",
      animation: 180,
      easing: "cubic-bezier(0.2, 0.8, 0.2, 1)",
      ghostClass: "ca-ghost",
      chosenClass: "ca-chosen",
      dragClass: "ca-drag",
      fallbackOnBody: true,
      forceFallback: true,
      fallbackTolerance: 4,
      onStart: () => {
        document.body.classList.add("ca-dragging")
        document.querySelectorAll("[data-cycle-action-sortable-target='list']").forEach(el => {
          el.classList.add("ca-droppable")
        })
        this.element.classList.add("ca-source")
      },
      onEnd: (evt) => {
        document.body.classList.remove("ca-dragging")
        document.querySelectorAll(".ca-droppable").forEach(el => el.classList.remove("ca-droppable", "ca-source", "ca-over"))
        this.persist(evt)
      },
    })

    this.element.addEventListener("dragenter", this.onDragEnter)
    this.element.addEventListener("dragleave", this.onDragLeave)
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
    this.element.removeEventListener("dragenter", this.onDragEnter)
    this.element.removeEventListener("dragleave", this.onDragLeave)
  }

  onDragEnter = () => {
    this.element.classList.add("ca-over")
  }
  onDragLeave = (e) => {
    if (!this.element.contains(e.relatedTarget)) {
      this.element.classList.remove("ca-over")
    }
  }

  async persist(evt) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const moves = []
    const dest = evt.to
    const src = evt.from
    moves.push(this._payloadFor(dest))
    if (src !== dest) moves.push(this._payloadFor(src))

    // Optimistic UI
    this._updateCounts(dest)
    if (src !== dest) this._updateCounts(src)
    this._refreshTotal()

    await Promise.all(moves.map(body =>
      fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrf,
        },
        body: JSON.stringify(body),
      })
    ))
  }

  _payloadFor(listEl) {
    const ids = Array.from(listEl.querySelectorAll("[data-cycle-action-sortable-target='item']"))
      .map(el => el.dataset.id)
    return {
      ids,
      category: listEl.dataset.cycleActionSortableCategoryValue,
      human_id: listEl.dataset.cycleActionSortableHumanIdValue,
    }
  }

  _updateCounts(listEl) {
    const category = listEl.dataset.cycleActionSortableCategoryValue
    const items = listEl.querySelectorAll("[data-cycle-action-sortable-target='item']")
    let count = 0
    let hours = 0
    items.forEach(el => {
      if (el.dataset.completed === "true") return
      count += 1
      hours += parseFloat(el.dataset.hours || "0") || 0
    })
    const pill = document.getElementById(`category_${category}_count`)
    if (!pill) return

    // Rebuild pill content safely (no innerHTML)
    pill.replaceChildren()
    const countSpan = document.createElement("span")
    countSpan.className = "font-medium"
    countSpan.textContent = String(count)
    pill.appendChild(countSpan)

    if (hours > 0) {
      const dot = document.createElement("span")
      dot.className = "text-gray-300"
      dot.textContent = "·"
      pill.appendChild(dot)

      const hoursWrap = document.createElement("span")
      const hoursVal = document.createElement("span")
      hoursVal.className = "font-semibold"
      const h = Number.isInteger(hours) ? hours : parseFloat(hours.toFixed(1))
      hoursVal.textContent = String(h)
      const unit = document.createElement("span")
      unit.className = "text-gray-400 ml-0.5"
      unit.textContent = "h"
      hoursWrap.appendChild(hoursVal)
      hoursWrap.appendChild(unit)
      pill.appendChild(hoursWrap)
    }
  }

  _refreshTotal() {
    const items = document.querySelectorAll("[data-cycle-action-sortable-target='item']")
    let total = 0
    items.forEach(el => {
      if (el.dataset.completed === "true") return
      const list = el.closest("[data-cycle-action-sortable-target='list']")
      if (!list) return
      if (list.dataset.cycleActionSortableCategoryValue === "reportee") return
      total += parseFloat(el.dataset.hours || "0") || 0
    })
    const span = document.querySelector("#hours_total .ca-engaged-value")
    if (span) span.textContent = Number.isInteger(total) ? String(total) : String(parseFloat(total.toFixed(1)))
  }
}
