import { Controller } from "@hotwired/stimulus"

// Grille « Espaces » — la ligne, pas seulement la cellule (epic #234, phase 3).
//
// Trois gestes vivent ici, au-dessus des `public--space-slot` de chaque case :
//   · « Tous les jours » pose « journée » sur les cases ENCORE VIDES d'une ligne
//     (une soirée déjà choisie n'est pas écrasée) ;
//   · « Effacer » vide la ligne ;
//   · le résumé en clair sous la grille se recalcule à chaque changement.
// La navigation par flèches reste, pour les séjours de plus de 7 jours.
//
// Les cases ne sont pas pilotées à la main : on leur envoie un événement
// `spaces-calendar:set`, que `space_slot_controller` traite comme un clic — une
// seule écriture de l'état, un seul endroit qui redessine.
const DAY_PERIODS = ["journee", "journee_et_soiree"]
const EVENING_PERIODS = ["soiree", "journee_et_soiree"]

export default class extends Controller {
  static targets = ["scrollArea", "cell", "summary"]
  static SCROLL_AMOUNT = 4 * 104 // 4 colonnes × 104px

  connect() {
    this.refreshSummary()
  }

  prevNights() {
    this.scroll(-this.constructor.SCROLL_AMOUNT)
  }

  nextNights() {
    this.scroll(this.constructor.SCROLL_AMOUNT)
  }

  scroll(amount) {
    if (this.hasScrollAreaTarget) {
      this.scrollAreaTarget.scrollBy({ left: amount, behavior: "smooth" })
    }
  }

  fillRow(event) {
    this.cellsFor(event.params.key).forEach((cell) => {
      if (!this.periodOf(cell)) this.setCell(cell, "journee")
    })
    this.refreshSummary()
  }

  clearRow(event) {
    this.cellsFor(event.params.key).forEach((cell) => this.setCell(cell, ""))
    this.refreshSummary()
  }

  // Une case a changé (clic direct ou geste de ligne) : le résumé suit.
  // `space_slot` émet un `change` qui REMONTE — le même que celui qui
  // rafraîchit le devis. On l'écoute donc sur la racine de la grille plutôt que
  // de rebrancher chaque cellule.
  slotChanged() {
    this.refreshSummary()
  }

  cellsFor(key) {
    return this.cellTargets.filter((cell) => cell.dataset.spaceKey === key)
  }

  periodOf(cell) {
    const input = cell.querySelector("input[type=hidden]")
    return input ? input.value || "" : ""
  }

  setCell(cell, period) {
    cell.dispatchEvent(new CustomEvent("spaces-calendar:set", { detail: { period } }))
  }

  // « Petite Salle · 5 journées · + 2 soirées · lun 8 → ven 12 ». Même format
  // que `SpacesGridHelper#spaces_summary_line`, qui rend la version initiale.
  refreshSummary() {
    if (!this.hasSummaryTarget) return

    this.summaryTarget.querySelectorAll("[data-summary-for]").forEach((line) => {
      const cells = this.cellsFor(line.dataset.summaryFor)
      const chosen = cells.filter((cell) => this.periodOf(cell) !== "")
      const detail = line.querySelector("[data-summary-detail]")

      if (chosen.length === 0) {
        line.classList.add("hidden")
        if (detail) detail.textContent = ""
        return
      }

      const periods = cells.map((cell) => this.periodOf(cell))
      const days = periods.filter((p) => DAY_PERIODS.includes(p)).length
      const evenings = periods.filter((p) => EVENING_PERIODS.includes(p)).length

      const parts = []
      if (days > 0) parts.push(count(days, "journée"))
      if (evenings > 0) parts.push(`+ ${count(evenings, "soirée")}`)

      const first = chosen[0].dataset.dayLabel
      const last = chosen[chosen.length - 1].dataset.dayLabel
      parts.push(first === last ? first : `${first} → ${last}`)

      line.classList.remove("hidden")
      if (detail) detail.textContent = ` · ${parts.join(" · ")}`
    })
  }
}

function count(n, singular) {
  return `${n} ${n > 1 ? `${singular}s` : singular}`
}
