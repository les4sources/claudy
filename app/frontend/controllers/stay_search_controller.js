import { Controller } from "@hotwired/stimulus"

// Autocomplete « Séjour » du formulaire Cuisine (epic #219). Le <select> natif
// listait jusqu'à 300 séjours triés par date d'arrivée : sur mobile c'est une
// roue interminable, et le nom cherché est n'importe où. On cherche côté serveur
// (Stays::Search) sur le nom du client, le nom du groupe porté par sa
// réservation, l'email et le téléphone.
//
// Même contrat que customer_search_controller : la source de vérité reste le
// <select name="meal_order[stay_id]">, toujours soumis ; le contrôleur le masque
// quand JS est actif et pilote sa valeur. Sans JS, le <select> reste utilisable.
export default class extends Controller {
  static targets = ["select", "searchWrap", "searchInput", "results", "chosen", "chosenLabel", "chosenContact"]
  static values = { url: String }

  connect() {
    this.selectTarget.classList.add("hidden")
    if (this.selectTarget.value) {
      this.showChosen(this.selectedLabel())
    } else {
      this.showSearch()
    }
  }

  search() {
    clearTimeout(this._timer)
    const q = this.searchInputTarget.value.trim()
    if (q.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }
    this._timer = setTimeout(() => this.runSearch(q), 250)
  }

  // Entrée dans un champ de recherche soumettrait le formulaire (soumission
  // implicite) alors qu'aucun séjour n'est encore choisi. On prend le premier
  // résultat à la place.
  pickFirst(event) {
    event.preventDefault()
    this.resultsTarget.querySelector("button")?.click()
  }

  async runSearch(q) {
    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" },
      })
      this.renderResults(await response.json())
    } catch (_e) {
      this.resultsTarget.innerHTML = ""
    }
  }

  renderResults(stays) {
    if (!stays.length) {
      this.resultsTarget.innerHTML = '<div class="px-3 py-2 text-sm text-gray-500">Aucun séjour trouvé.</div>'
      return
    }
    this.resultsTarget.innerHTML = stays
      .map((stay) => {
        const details = [stay.group, stay.contact].filter(Boolean).map((v) => this.escape(v)).join(" · ")
        return `<button type="button" data-action="stay-search#pick" data-id="${stay.id}" data-label="${this.escape(stay.label)}" data-contact="${this.escape(details)}" class="block w-full text-left px-3 py-2 text-sm hover:bg-indigo-50">
          <span class="block font-medium text-gray-900">${this.escape(stay.label)}</span>
          <span class="block text-gray-400">${details}</span>
        </button>`
      })
      .join("")
  }

  pick(event) {
    const { id, label, contact } = event.currentTarget.dataset
    this.setSelectValue(id, label)
    this.showChosen(label, contact)
    this.resultsTarget.innerHTML = ""
    this.searchInputTarget.value = ""
  }

  clear() {
    this.selectTarget.value = ""
    this.showSearch()
    this.searchInputTarget.focus()
  }

  setSelectValue(id, label) {
    let option = Array.from(this.selectTarget.options).find((o) => o.value === String(id))
    if (!option) {
      option = new Option(label, id)
      this.selectTarget.add(option)
    }
    this.selectTarget.value = String(id)
  }

  selectedLabel() {
    const option = this.selectTarget.selectedOptions[0]
    return option ? option.textContent.trim() : ""
  }

  showChosen(label, contact = null) {
    this.chosenLabelTarget.textContent = label
    if (contact !== null) this.chosenContactTarget.textContent = contact
    this.chosenTarget.classList.remove("hidden")
    this.searchWrapTarget.classList.add("hidden")
  }

  showSearch() {
    this.chosenTarget.classList.add("hidden")
    this.searchWrapTarget.classList.remove("hidden")
    this.resultsTarget.innerHTML = ""
  }

  escape(str) {
    const div = document.createElement("div")
    div.textContent = str ?? ""
    return div.innerHTML
  }
}
