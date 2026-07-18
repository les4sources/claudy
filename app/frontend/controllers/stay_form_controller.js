import { Controller } from "@hotwired/stimulus"

// Formulaire CRUD Séjour admin (epic #66, Phase 1). Bascule client existant /
// nouveau client : seul le panneau actif est visible (les deux restent dans le
// DOM, le contrôleur ne soumet pas côté client — c'est `customer_mode` qui dit
// au serveur quel panneau lire).
//
// Usage (dans stays/_form) :
//   form(data-controller="stay-form")
//     input[type=radio name="stay[customer_mode]"] (data-action="change->stay-form#toggleCustomer")
//     div(data-stay-form-target="existingPanel")
//     div(data-stay-form-target="newPanel")
export default class extends Controller {
  static targets = ["existingPanel", "newPanel"]

  connect() {
    this.toggleCustomer()
  }

  toggleCustomer() {
    const mode =
      this.element.querySelector('input[name="stay[customer_mode]"]:checked')?.value ||
      "existing"
    this.togglePanel(this.existingPanelTarget, mode === "existing")
    this.togglePanel(this.newPanelTarget, mode === "new")
  }

  togglePanel(panel, active) {
    if (!panel) return
    panel.classList.toggle("hidden", !active)
  }
}
