import { Controller } from "@hotwired/stimulus"

// Services annexes d'un séjour (Michael, 2026-10-23) : choisir un service du
// catalogue préremplit le libellé et le montant de la ligne, qui restent
// modifiables. Revenir à « Ligne libre » ne vide rien : ce qu'on a tapé reste.
export default class extends Controller {
  static targets = ["label", "amount"]

  prefill(event) {
    const option = event.target.selectedOptions?.[0]
    if (!option || option.value === "") return

    if (option.dataset.label) this.labelTarget.value = option.dataset.label
    if (option.dataset.amount) this.amountTarget.value = option.dataset.amount
  }
}
