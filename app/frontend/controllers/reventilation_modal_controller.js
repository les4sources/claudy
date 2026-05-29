import { Controller } from "@hotwired/stimulus"

// Modale de re-ventilation des séjours d'un client (fourre-tout) vers une cible.
// Deux modes exclusifs — client existant ou nouveau client ; seul le panneau
// actif a ses champs activés, donc seul lui est soumis avec le formulaire.
//
// Usage:
//   div(data-controller="reventilation-modal")
//     button(data-action="reventilation-modal#open")
//     dialog(data-reventilation-modal-target="dialog")
//       input[type=radio name=mode] (data-action="reventilation-modal#switchMode")
//       fieldset(data-reventilation-modal-target="existingPanel")
//       fieldset(data-reventilation-modal-target="newPanel")
export default class extends Controller {
  static targets = ["dialog", "existingPanel", "newPanel"]

  open(event) {
    event.preventDefault()
    this.switchMode()
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }

  // Enable only the active panel's fields so the inactive ones aren't submitted.
  switchMode() {
    const mode = this.element.querySelector('input[name="mode"]:checked')?.value || "existing"
    this.togglePanel(this.existingPanelTarget, mode === "existing")
    this.togglePanel(this.newPanelTarget, mode === "new")
  }

  togglePanel(panel, active) {
    if (!panel) return
    panel.classList.toggle("hidden", !active)
    panel.querySelectorAll("input, select, textarea").forEach((field) => {
      field.disabled = !active
    })
  }
}
