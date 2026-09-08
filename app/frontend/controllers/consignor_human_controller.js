import { Controller } from "@hotwired/stimulus"

// Formulaire d'un artisan en dépôt-vente (epic #248, phase 1).
//
// Deux services : choisir un membre de l'équipe pré-remplit son nom et son
// email (sans jamais écraser une saisie déjà faite), et le bloc IBAN ne
// s'affiche que pour un règlement par virement — c'est le seul mode où on en a
// besoin.
export default class extends Controller {
  static targets = ["select", "name", "email", "ibanField"]

  connect() {
    this.toggleIban()
  }

  fill() {
    const option = this.selectTarget.selectedOptions[0]
    if (!option || !option.value) return

    if (this.hasNameTarget && !this.nameTarget.value) {
      this.nameTarget.value = option.dataset.name || ""
    }
    if (this.hasEmailTarget && !this.emailTarget.value) {
      this.emailTarget.value = option.dataset.email || ""
    }
  }

  toggleIban(event) {
    if (!this.hasIbanFieldTarget) return

    const mode = event ? event.target.value : this.currentMode()
    this.ibanFieldTarget.hidden = mode !== "transfer"
  }

  currentMode() {
    const select = this.element.querySelector("select[name$='[settlement_mode]']")
    return select ? select.value : "transfer"
  }
}
