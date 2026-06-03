import { Controller } from "@hotwired/stimulus"

// Grille « calendrier de séjour » du funnel B2C /reservation : un tableau dont
// les colonnes sont les nuits du séjour et les lignes les hébergements (La
// Hulotte, La Chevêche, Le Grand-Duc). Chaque cellule est un <button> avec
// `aria-pressed`. La sélection d'un hébergement est EXCLUSIVE par nuit : une
// seule cellule peut être active dans une colonne donnée.
//
// Règle week-end : vendredi (wday=5) et samedi (wday=6) impliquent 2 nuits
// minimum pour le même hébergement. La sélection d'une nuit cascades
// automatiquement sur la nuit paire (sauf si elle est déjà occupée).
//
// À chaque toggle, on régénère intégralement le conteneur de champs cachés
// (`reservation[lodging_night_ids][]`) et on émet un `change` bouillonnant.
export default class extends Controller {
  static targets = ["hiddenFields"]
  static values  = { nights: Number, avail: Object }

  connect() {
    this.syncHiddenFields()
  }

  toggleLodging(event) {
    event.preventDefault()
    const cell      = event.currentTarget
    const nightIndex = parseInt(cell.getAttribute("data-night-index"), 10)
    const lodgingId  = cell.getAttribute("data-lodging-id")
    const isPressed  = cell.getAttribute("aria-pressed") === "true"

    if (isPressed) {
      this.setCellState(cell, false)
      this.clearWeekendPair(lodgingId, nightIndex)
    } else {
      const current = this.selectedCellForNight(String(nightIndex))
      if (current && current !== cell) this.setCellState(current, false)
      this.setCellState(cell, true)
      this.cascadeWeekend(lodgingId, nightIndex)
    }

    this.syncHiddenFields()
    this.dispatchChange()
  }

  // Si la nuit est ven ou sam, sélectionne aussi la nuit paire (si disponible).
  cascadeWeekend(lodgingId, nightIndex) {
    const wday = this.nightWday(nightIndex)
    let pairIndex = -1
    if (wday === 5) pairIndex = nightIndex + 1  // vendredi → samedi
    if (wday === 6) pairIndex = nightIndex - 1  // samedi → vendredi
    if (pairIndex < 0 || pairIndex >= this.nightsValue) return

    // Ne cascade pas si la nuit paire est indisponible (occupée côté admin)
    const availArr = (this.availValue || {})[lodgingId]
    if (Array.isArray(availArr) && availArr[pairIndex] === false) return

    const targetCell = this.lodgingCellAt(lodgingId, pairIndex)
    if (!targetCell || targetCell.disabled) return

    const existing = this.selectedCellForNight(String(pairIndex))
    if (existing && existing !== targetCell) this.setCellState(existing, false)
    if (targetCell.getAttribute("aria-pressed") !== "true") {
      this.setCellState(targetCell, true)
    }
  }

  // Si la nuit désélectionnée était en paire week-end, désélectionne aussi le pair.
  clearWeekendPair(lodgingId, nightIndex) {
    const wday = this.nightWday(nightIndex)
    let pairIndex = -1
    if (wday === 5) pairIndex = nightIndex + 1
    if (wday === 6) pairIndex = nightIndex - 1
    if (pairIndex < 0 || pairIndex >= this.nightsValue) return

    const pairCell = this.selectedCellForNight(String(pairIndex))
    if (pairCell && pairCell.getAttribute("data-lodging-id") === lodgingId) {
      this.setCellState(pairCell, false)
    }
  }

  selectedCellForNight(nightIndex) {
    for (const cell of this.lodgingCells()) {
      if (
        cell.getAttribute("data-night-index") === nightIndex &&
        cell.getAttribute("aria-pressed") === "true"
      ) return cell
    }
    return null
  }

  lodgingCells() {
    return this.element.querySelectorAll('[data-type="lodging"]')
  }

  lodgingCellAt(lodgingId, nightIndex) {
    return this.element.querySelector(
      `[data-type="lodging"][data-lodging-id="${lodgingId}"][data-night-index="${nightIndex}"]`
    )
  }

  nightWday(nightIndex) {
    const th = this.element.querySelector(`th[data-wday]`)
    const ths = Array.from(this.element.querySelectorAll("th[data-wday]"))
    if (ths[nightIndex]) return parseInt(ths[nightIndex].getAttribute("data-wday"), 10)
    return -1
  }

  // Classes identiques à celles du template Slim — source de vérité unique.
  setCellState(cell, selected) {
    const selectedClasses = ["bg-emerald-500", "border-emerald-500", "text-white", "shadow-sm"]
    const idleClasses = ["bg-white", "border-gray-200", "text-gray-300", "hover:border-emerald-400", "hover:bg-emerald-50"]

    cell.setAttribute("aria-pressed", selected ? "true" : "false")
    cell.textContent = selected ? "✓" : ""

    if (selected) {
      cell.classList.remove(...idleClasses)
      cell.classList.add(...selectedClasses)
    } else {
      cell.classList.remove(...selectedClasses)
      cell.classList.add(...idleClasses)
    }
  }

  syncHiddenFields() {
    if (!this.hasHiddenFieldsTarget) return

    const selectionByNight = new Map()
    for (const cell of this.lodgingCells()) {
      if (cell.getAttribute("aria-pressed") !== "true") continue
      const nightIndex = cell.getAttribute("data-night-index")
      const lodgingId  = cell.getAttribute("data-lodging-id")
      if (nightIndex === null) continue
      selectionByNight.set(nightIndex, lodgingId ?? "")
    }

    const container = this.hiddenFieldsTarget
    container.replaceChildren()

    const count = Number.isFinite(this.nightsValue) ? Math.max(0, Math.trunc(this.nightsValue)) : 0

    for (let night = 0; night < count; night += 1) {
      const input = document.createElement("input")
      input.type  = "hidden"
      input.name  = "reservation[lodging_night_ids][]"
      input.value = selectionByNight.get(String(night)) ?? ""
      container.appendChild(input)
    }
  }

  dispatchChange() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
