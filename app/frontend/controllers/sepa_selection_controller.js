import { Controller } from "@hotwired/stimulus"

// Les virements cochés de la file « À payer » (Michael, 2026-11-05) : combien,
// pour quel total, avant de générer le fichier SEPA. Le bouton reste éteint
// tant que rien n'est coché — un fichier vide, la banque le refuse.
//
// Chaque case porte son montant en centimes (`data-cents`). Le serveur relit
// tout : ce compteur n'est qu'un repère pour l'œil.
export default class extends Controller {
  static targets = ["checkbox", "count", "total", "submit", "toggle"]

  connect() {
    this.refresh()
  }

  toggleAll() {
    const enabled = this.checkboxTargets.filter((box) => !box.disabled)
    const check = enabled.some((box) => !box.checked)
    enabled.forEach((box) => { box.checked = check })
    this.refresh()
  }

  refresh() {
    const checked = this.checkboxTargets.filter((box) => box.checked && !box.disabled)
    const cents = checked.reduce((sum, box) => sum + Number(box.dataset.cents || 0), 0)

    if (this.hasCountTarget) {
      this.countTarget.textContent = checked.length === 0
        ? "Aucun virement coché"
        : `${checked.length} virement${checked.length > 1 ? "s" : ""} coché${checked.length > 1 ? "s" : ""}`
    }
    if (this.hasTotalTarget) {
      this.totalTarget.textContent = new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" }).format(cents / 100)
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = checked.length === 0
    if (this.hasToggleTarget) {
      const enabled = this.checkboxTargets.filter((box) => !box.disabled)
      this.toggleTarget.textContent = enabled.length > 0 && enabled.every((box) => box.checked) ? "Tout décocher" : "Tout cocher"
    }
  }
}
