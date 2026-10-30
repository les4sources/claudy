import { Controller } from "@hotwired/stimulus"

// Le montant à ventiler sur un séjour suit le séjour choisi (Michael,
// 2026-10-30). Chaque option porte ce que son séjour attend encore, plafonné
// à ce que la ligne porte : 74 € reçus pour un séjour de 70 € en proposent
// 70, le reste s'affecte ensuite à la main. Sans séjour, toute la ligne.
export default class extends Controller {
  static targets = ["select", "amount"]
  static values = { default: String }

  follow() {
    const option = this.selectTarget.selectedOptions[0]
    this.amountTarget.value = option?.dataset.amount || this.defaultValue
  }
}
