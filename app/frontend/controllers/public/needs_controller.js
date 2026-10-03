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

    // Une puce par bloc, toujours visible : pleine (aria-pressed) quand le bloc
    // fait partie du séjour, « + » sinon. On masquait les puces actives avec
    // l'attribut `hidden`, que la classe `inline-flex` écrasait : « + Gîte »
    // restait affiché alors que le gîte était déjà là, et le clic ne faisait
    // rien. La zone reste masquée quand rien n'a été coché (tout est visible).
    this.addButtons().forEach((btn) => {
      const active = this.empty || this.selected.has(btn.dataset.needsAddToken)
      btn.setAttribute("aria-pressed", active ? "true" : "false")
    })
    if (this.hasAddZoneTarget) this.addZoneTarget.hidden = this.empty

    this.syncFields()
  }

  add(event) {
    event.preventDefault()
    const token = event.currentTarget.dataset.needsAddToken
    if (!token) return
    if (!this.selected.has(token)) {
      this.selected.add(token)
      this.apply()
    }
    this.reveal(token)
  }

  // Amène le bloc du besoin à l'écran : on voit tout de suite où il est.
  reveal(token) {
    const block = this.element.querySelector(`[data-needs-block~="${token}"]:not([hidden])`)
    if (!block) return
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    block.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
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
