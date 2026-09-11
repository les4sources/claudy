import { Controller } from "@hotwired/stimulus"

// La grille de comptage de la caisse (epic #243, phase 3).
//
// Le total et l'écart se calculent PENDANT qu'on tape : compter un tiroir en
// aveugle, valider, puis découvrir l'écart sur l'écran suivant, c'est ce qui
// fait qu'on ne recompte pas. Le serveur refait le calcul de son côté — celui-ci
// n'est qu'un confort de saisie.
export default class extends Controller {
  static targets = ["quantity", "total", "difference", "verdict", "resolution"]
  static values = { expectedCents: Number }

  connect() {
    this.refresh()
  }

  refresh() {
    const countedCents = this.quantityTargets.reduce((sum, input) => {
      const unitCents = parseInt(input.dataset.unitCents, 10) || 0
      const quantity = parseInt(input.value, 10) || 0
      return sum + unitCents * quantity
    }, 0)

    const differenceCents = countedCents - this.expectedCentsValue

    this.totalTarget.textContent = this.format(countedCents)
    this.differenceTarget.textContent = this.formatSigned(differenceCents)

    if (this.hasVerdictTarget) {
      this.verdictTarget.textContent = this.verdict(differenceCents)
      this.verdictTarget.className = differenceCents === 0
        ? "text-sm font-medium text-emerald-700"
        : "text-sm font-medium text-orange-700"
    }

    // Le choix forcé n'apparaît que s'il y a un écart : demander « que fais-tu
    // de cet écart ? » sur une caisse juste n'aurait aucun sens.
    if (this.hasResolutionTarget) {
      this.resolutionTarget.hidden = differenceCents === 0
    }
  }

  verdict(differenceCents) {
    if (differenceCents === 0) return "La caisse tombe juste."
    if (differenceCents > 0) return "Il y a plus dans le tiroir que ce que la comptabilité attend."
    return "Il manque de l'argent dans le tiroir."
  }

  format(cents) {
    return new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" }).format(cents / 100)
  }

  formatSigned(cents) {
    const sign = cents > 0 ? "+" : cents < 0 ? "−" : ""
    return `${sign}${this.format(Math.abs(cents))}`
  }
}
