import { Controller } from "@hotwired/stimulus"

// Saisie d'une action de cycle : durée d'UNE fois × nombre de fois dans le
// cycle (issue #338). Le total affiché suit la frappe et utilise le même
// arrondi que le serveur (2 décimales, zéros non significatifs retirés).
export default class extends Controller {
  static targets = ["unitHours", "occurrences", "total"]

  connect() {
    this.refresh()
  }

  increment() {
    this.setOccurrences(this.occurrences + 1)
  }

  decrement() {
    this.setOccurrences(this.occurrences - 1)
  }

  refresh() {
    if (!this.hasTotalTarget) return

    const unit = this.unitHours
    const times = this.occurrences

    if (times <= 1 || unit <= 0) {
      this.totalTarget.textContent = ""
      return
    }
    this.totalTarget.textContent = `= ${this.format(unit * times)} h`
  }

  // Le multiplicateur ne descend jamais sous 1 : « zéro fois », ça n'existe pas.
  setOccurrences(value) {
    if (!this.hasOccurrencesTarget) return
    this.occurrencesTarget.value = Math.max(1, value)
    this.refresh()
  }

  get unitHours() {
    if (!this.hasUnitHoursTarget) return 0
    const parsed = parseFloat(String(this.unitHoursTarget.value).replace(",", "."))
    return Number.isFinite(parsed) ? parsed : 0
  }

  get occurrences() {
    if (!this.hasOccurrencesTarget) return 1
    const parsed = parseInt(this.occurrencesTarget.value, 10)
    return Number.isFinite(parsed) && parsed >= 1 ? parsed : 1
  }

  format(value) {
    return String(parseFloat(value.toFixed(2)))
  }
}
