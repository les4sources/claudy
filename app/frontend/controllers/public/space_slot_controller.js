import { Controller } from "@hotwired/stimulus"

// Cellule de la grille "Espaces" du funnel B2C. Gère un seul créneau
// (un espace × une nuit). Clic = cycle — → Journée → Soirée → J+S → —.
// Un input[type=hidden] synchronisé transmet la valeur au formulaire ;
// un bouton visuel affiche l'état courant avec la bonne couleur.
const PERIODS = ["", "journee", "soiree", "journee_et_soiree"]
const LABELS  = { "": "—", "journee": "Jour", "soiree": "Soir", "journee_et_soiree": "J+S" }
const STATE_CLASSES = {
  "":                  "bg-white border-gray-200 text-gray-300 hover:border-blue-300",
  "journee":           "bg-blue-100 border-blue-300 text-blue-700",
  "soiree":            "bg-purple-100 border-purple-300 text-purple-700",
  "journee_et_soiree": "bg-teal-100 border-teal-300 text-teal-700"
}

export default class extends Controller {
  static targets = ["button", "input"]

  connect() {
    this.updateDisplay(this.inputTarget.value || "")
  }

  toggle() {
    const current = this.inputTarget.value || ""
    const idx  = PERIODS.indexOf(current)
    const next = PERIODS[(idx + 1) % PERIODS.length]
    this.inputTarget.value = next
    this.updateDisplay(next)
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  updateDisplay(period) {
    const btn = this.buttonTarget
    btn.textContent = LABELS[period] ?? "—"
    const allClasses = Object.values(STATE_CLASSES).join(" ").split(" ")
    allClasses.forEach(c => btn.classList.remove(c))
    const classes = (STATE_CLASSES[period] ?? STATE_CLASSES[""]).split(" ")
    classes.forEach(c => btn.classList.add(c))
  }
}
