import { Controller } from "@hotwired/stimulus"

// Masquage/affichage des blocs de l'étape 2 selon les BESOINS cochés à l'étape 1
// (feature 5). Chaque bloc porte `data-needs-block="token[ token…]"` ; un bloc
// est visible si AUCUN besoin n'est coché (comportement conservateur) OU si l'un
// de ses tokens fait partie de la sélection. Chaque bloc masqué peut être
// redéployé via un bouton « + Ajouter » (`data-needs-add-token`), sans revenir
// en arrière. La sélection est rejouée dans des champs cachés
// `reservation[needs][]` pour survivre aux allers-retours (devis / étape suivante).
export default class extends Controller {
  static targets = ["fields", "addZone"]
  static values = { selected: Array }

  connect() {
    this.selected = new Set((this.selectedValue || []).map(String))
    this.apply()
  }

  get empty() {
    return this.selected.size === 0
  }

  blocks() {
    return this.element.querySelectorAll("[data-needs-block]")
  }

  addButtons() {
    return this.element.querySelectorAll("[data-needs-add-token]")
  }

  visibleFor(tokens) {
    if (this.empty) return true
    return tokens.some((t) => this.selected.has(t))
  }

  apply() {
    this.blocks().forEach((el) => {
      const tokens = (el.dataset.needsBlock || "").split(/\s+/).filter(Boolean)
      el.hidden = !this.visibleFor(tokens)
    })

    let anyAdd = false
    this.addButtons().forEach((btn) => {
      const token = btn.dataset.needsAddToken
      const show = !this.empty && !this.selected.has(token)
      btn.hidden = !show
      if (show) anyAdd = true
    })
    if (this.hasAddZoneTarget) this.addZoneTarget.hidden = !anyAdd

    this.syncFields()
  }

  add(event) {
    event.preventDefault()
    const token = event.currentTarget.dataset.needsAddToken
    if (!token) return
    this.selected.add(token)
    this.apply()
  }

  // Champs cachés `reservation[needs][]` reconstruits à chaque changement — la
  // sélection (initiale + blocs ajoutés) survit ainsi au POST devis / étape 3.
  syncFields() {
    if (!this.hasFieldsTarget) return
    this.fieldsTarget.replaceChildren()
    this.selected.forEach((token) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "reservation[needs][]"
      input.value = token
      this.fieldsTarget.appendChild(input)
    })
  }
}
