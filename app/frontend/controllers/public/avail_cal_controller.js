import { Controller } from "@hotwired/stimulus"

// Met en évidence une colonne du Gantt de disponibilités au clic.
// Les cellules portent data-date="YYYY-MM-DD". Un clic sélectionne la colonne
// via une ligne bleue en haut de chaque cellule (border-top). Les autres colonnes
// restent à pleine opacité — approche "illumination" plutôt que "assombrissement".
// Re-clic sur la même date désélectionne.
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

    this.element.querySelectorAll("[data-date]").forEach(cell => {
      if (cell.dataset.date === date) {
        cell.style.borderTop = "3px solid #0ea5e9"  // sky-500
      } else {
        cell.style.borderTop = ""
      }
    })

    if (this.hasDayLabelTarget) {
      this.dayLabelTarget.textContent = "📅 " + this.formatFr(date)
      this.dayLabelTarget.classList.remove("hidden")
    }
  }

  clearSelection() {
    delete this.element.dataset.selectedDate

    this.element.querySelectorAll("[data-date]").forEach(cell => {
      cell.style.borderTop = ""
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
