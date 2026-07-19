import { Controller } from "@hotwired/stimulus"

// Autocomplete « Client existant » du form Séjour admin (issue #74). Remplace le
// <select> listant tous les clients par une recherche dynamique sur
// customers/search (fetch JSON, debounce ~250 ms). La source de vérité reste le
// <select name="stay[customer_id]"> (toujours soumis) : le contrôleur le masque
// quand JS est actif et pilote sa valeur à la sélection. Sans JS, le <select>
// (réduit au client courant) reste utilisable — dégradation gracieuse.
//
// Usage (dans stays/_form) :
//   div(data-controller="customer-search" data-customer-search-url-value="<%= search_customers_path %>")
//     select[name="stay[customer_id]"] (data-customer-search-target="select")
//     div(data-customer-search-target="searchWrap")
//       input(data-customer-search-target="searchInput" data-action="input->customer-search#search")
//       div(data-customer-search-target="results")
//     div(data-customer-search-target="chosen")
//       span(data-customer-search-target="chosenLabel")
//       button(data-action="customer-search#clear")
export default class extends Controller {
  static targets = ["select", "searchWrap", "searchInput", "results", "chosen", "chosenLabel"]
  static values = { url: String }

  connect() {
    // JS actif : on masque le <select> de repli et on montre la recherche.
    this.selectTarget.classList.add("hidden")
    if (this.selectTarget.value) {
      // Édition : un client est déjà sélectionné → afficher son libellé.
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

  renderResults(customers) {
    if (!customers.length) {
      this.resultsTarget.innerHTML = '<div class="px-3 py-2 text-sm text-gray-500">Aucun client trouvé.</div>'
      return
    }
    this.resultsTarget.innerHTML = customers
      .map(
        (c) =>
          `<button type="button" data-action="customer-search#pick" data-id="${c.id}" data-label="${this.escape(c.name || c.email)}" class="block w-full text-left px-3 py-2 text-sm hover:bg-indigo-50">${this.escape(c.name || "")} <span class="text-gray-400">${this.escape(c.email || "")}</span></button>`
      )
      .join("")
  }

  pick(event) {
    const { id, label } = event.currentTarget.dataset
    this.setSelectValue(id, label)
    this.showChosen(label)
    this.resultsTarget.innerHTML = ""
    this.searchInputTarget.value = ""
  }

  clear() {
    this.selectTarget.value = ""
    this.showSearch()
    this.searchInputTarget.focus()
  }

  // Garantit une <option> pour l'id choisi puis la sélectionne (le <select>
  // porte name="stay[customer_id]" et est la valeur soumise).
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

  showChosen(label) {
    if (this.hasChosenLabelTarget) this.chosenLabelTarget.textContent = label
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
