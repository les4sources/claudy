import { Controller } from "@hotwired/stimulus"

// Met en évidence une colonne du Gantt de disponibilités au clic.
// Les cellules portent data-date="YYYY-MM-DD". Un clic sélectionne la colonne
// (ring bleu + autres colonnes en opacity-40). Re-clic sur la même date déselectionne.
export default class extends Controller {
  static targets = ["dayLabel"]

  selectDay(event) {
    const clicked = event.currentTarget
    const date = clicked.dataset.date
    if (!date) return

    const current = this.element.dataset.selectedDate

    if (current === date) {
      this.clearSelection()
    } else {
      this.applySelection(date)
    }
  }

  applySelection(date) {
    this.element.dataset.selectedDate = date

    // Toutes les cellules dates
    const allCells = this.element.querySelectorAll("[data-date]")

    allCells.forEach(cell => {
      if (cell.dataset.date === date) {
        // Colonne sélectionnée : ring bleu + opacité normale
        cell.classList.add("ring-2", "ring-blue-500", "ring-inset")
        cell.classList.remove("opacity-30")
      } else {
        // Autres colonnes : griser légèrement
        cell.classList.remove("ring-2", "ring-blue-500", "ring-inset")
        cell.classList.add("opacity-30")
      }
    })

    // Afficher le label de date
    if (this.hasDayLabelTarget) {
      this.dayLabelTarget.textContent = "📅 " + this.formatFr(date)
      this.dayLabelTarget.classList.remove("hidden")
    }
  }

  clearSelection() {
    delete this.element.dataset.selectedDate

    this.element.querySelectorAll("[data-date]").forEach(cell => {
      cell.classList.remove("ring-2", "ring-blue-500", "ring-inset", "opacity-30")
    })

    if (this.hasDayLabelTarget) {
      this.dayLabelTarget.classList.add("hidden")
      this.dayLabelTarget.textContent = ""
    }
  }

  formatFr(isoDate) {
    const [y, m, d] = isoDate.split("-").map(Number)
    const months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    const days = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    const dt = new Date(y, m - 1, d)
    return days[dt.getDay()] + " " + d + " " + months[m - 1] + " " + y
  }
}
