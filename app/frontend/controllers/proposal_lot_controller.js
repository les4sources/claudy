import { Controller } from "@hotwired/stimulus"

// Un lot de la revue des propositions (Michael, 2026-11-26) : combien de
// lignes cochées, pour quel total, avant « Accepter les lignes cochées ».
// Une ligne acceptée ou refusée seule sort de la page sans rechargement :
// le compteur la retire avec elle.
//
// Chaque case porte son montant en centimes (`data-cents`). Le serveur relit
// tout : ce compteur n'est qu'un repère pour l'œil.
export default class extends Controller {
  static targets = ["checkbox", "count", "total", "submit", "toggle"]

  connect() {
    this.refresh()
  }

  checkboxTargetDisconnected() {
    this.refresh()
  }

  toggleAll() {
    const check = this.checkboxTargets.some((box) => !box.checked)
    this.checkboxTargets.forEach((box) => { box.checked = check })
    this.refresh()
  }

  refresh() {
    const checked = this.checkboxTargets.filter((box) => box.checked)
    const cents = checked.reduce((sum, box) => sum + Number(box.dataset.cents || 0), 0)

    if (this.hasCountTarget) {
      this.countTarget.textContent = checked.length === 0
        ? "Aucune ligne cochée"
        : `Accepter ${checked.length === 1 ? "la ligne cochée" : `les ${checked.length} lignes cochées`}`
    }
    if (this.hasTotalTarget) {
      this.totalTarget.textContent = new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" }).format(cents / 100)
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = checked.length === 0
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.checkboxTargets.length > 0 && this.checkboxTargets.every((box) => box.checked)
        ? "Tout décocher"
        : "Tout cocher"
    }
  }
}
