import { Controller } from "@hotwired/stimulus"

// Gère l'ajout/suppression dynamique de lignes de réservation d'espaces
// (salles + cuisine) dans le funnel B2C /reservation. La page démarre sans
// aucune ligne ; l'utilisateur en ajoute jusqu'à MAX_ROWS. L'indice de chaque
// ligne (`reservation[halls][N][...]`) s'incrémente de façon monotone et n'est
// jamais réutilisé après suppression — le serveur ignore les lignes vides.
// Chaque mutation déclenche un `change` qui remonte au formulaire parent afin
// de relancer le recalcul du devis (reservation_quote_controller).
export default class extends Controller {
  static targets = ["list", "addBtn"]
  static values  = { min: String, max: String }

  // Cap dur côté client : le serveur reste l'autorité, mais on borne l'UI.
  static MAX_ROWS = 6

  connect() {
    // Compteur monotone : on ne réutilise jamais un indice libéré, ce qui évite
    // les collisions de `name` quand une ligne du milieu est supprimée.
    this.nextIndex = 0
    // Direct addEventListener rather than data-action: the add button lives inside
    // both the hall-slots scope AND the parent reservation-quote scope, which would
    // cause Stimulus to create two Bindings and fire add() twice per click.
    if (this.hasAddBtnTarget) {
      this._onAddClick = (e) => { e.preventDefault(); this.add(e) }
      this.addBtnTarget.addEventListener("click", this._onAddClick)
    }
    this.syncAddButton()
  }

  disconnect() {
    if (this._onAddClick && this.hasAddBtnTarget) {
      this.addBtnTarget.removeEventListener("click", this._onAddClick)
    }
  }

  // Action — bouton « Ajouter un espace ».
  add(event) {
    if (event) event.preventDefault()
    if (this.rowCount() >= this.constructor.MAX_ROWS) return

    const index = this.nextIndex
    this.nextIndex += 1
    this.listTarget.appendChild(this.buildRow(index))
    this.syncAddButton()
    this.dispatchChange()
  }

  // Action — bouton « × » de chaque ligne.
  remove(event) {
    if (event) event.preventDefault()
    const row = event.currentTarget.closest("[data-hall-row]")
    if (!row) return
    row.remove()
    this.syncAddButton()
    this.dispatchChange()
  }

  // Construit une ligne complète : kind / date / period + bouton supprimer.
  buildRow(index) {
    const row = document.createElement("div")
    row.className = "flex gap-2 items-center p-3 bg-gray-50 rounded-lg border border-gray-200"
    row.setAttribute("data-hall-row", "")

    row.appendChild(this.buildKindSelect(index))
    row.appendChild(this.buildDateInput(index))
    row.appendChild(this.buildPeriodSelect(index))
    row.appendChild(this.buildRemoveButton())

    return row
  }

  buildKindSelect(index) {
    return this.buildSelect(
      `reservation[halls][${index}][kind]`,
      [
        ["— Espace —", ""],
        ["Grande salle", "grande_salle"],
        ["Petite salle", "petite_salle"],
        ["Cuisine pro", "cuisine_pro"]
      ]
    )
  }

  buildPeriodSelect(index) {
    return this.buildSelect(
      `reservation[halls][${index}][period]`,
      [
        ["— Période —", ""],
        ["Journée", "journee"],
        ["Soirée", "soiree"],
        ["Journée + Soirée", "journee_et_soiree"]
      ]
    )
  }

  buildSelect(name, options) {
    const select = document.createElement("select")
    select.name = name
    select.className = "flex-1 min-w-0 text-sm rounded-lg border-gray-300 bg-white focus:border-emerald-500 focus:ring-emerald-500"
    for (const [label, value] of options) {
      const option = document.createElement("option")
      option.textContent = label
      option.value = value
      select.appendChild(option)
    }
    return select
  }

  buildDateInput(index) {
    const input = document.createElement("input")
    input.type = "date"
    input.name = `reservation[halls][${index}][date]`
    input.className = "flex-1 min-w-0 text-sm rounded-lg border-gray-300 bg-white focus:border-emerald-500 focus:ring-emerald-500"
    // Bornes optionnelles : on ne pose l'attribut que si la value est fournie,
    // pour ne pas écrire `min=""`/`max=""` qui n'a pas de sens sur un date input.
    if (this.hasMinValue && this.minValue) input.min = this.minValue
    if (this.hasMaxValue && this.maxValue) input.max = this.maxValue
    return input
  }

  buildRemoveButton() {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "flex-shrink-0 text-gray-400 hover:text-red-500 transition-colors p-1"
    button.setAttribute("aria-label", "Supprimer cet espace")
    button.innerHTML = `<svg class="w-5 h-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" /></svg>`
    // Direct addEventListener instead of data-action to avoid Stimulus MutationObserver
    // re-scanning the add button and creating a duplicate Binding.
    button.addEventListener("click", (e) => { e.preventDefault(); this.remove(e) })
    return button
  }

  // Nombre de lignes effectivement présentes dans le DOM (source de vérité, vs
  // le compteur monotone qui, lui, ne décroît jamais).
  rowCount() {
    return this.listTarget.querySelectorAll("[data-hall-row]").length
  }

  // Active/désactive le bouton « Ajouter » selon le cap MAX_ROWS.
  syncAddButton() {
    if (!this.hasAddBtnTarget) return
    const atMax = this.rowCount() >= this.constructor.MAX_ROWS
    this.addBtnTarget.disabled = atMax
    this.addBtnTarget.classList.toggle("opacity-50", atMax)
  }

  // Remonte un `change` bouillonnant au formulaire parent pour recalculer le
  // devis. On vise le <form> ancêtre ; à défaut, on émet depuis l'élément du
  // controller (le bubbling atteindra quand même les listeners en amont).
  dispatchChange() {
    const target = this.element.closest("form") || this.element
    target.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
