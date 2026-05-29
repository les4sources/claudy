import { Controller } from "@hotwired/stimulus"

// Formulaire de réassignation d'UN séjour depuis la modale de détails.
// Deux modes exclusifs (client existant via recherche dynamique / nouveau client),
// seul le panneau actif est soumis. La recherche interroge /customers/search.
//
// Usage (dans le fragment stays/show) :
//   form(data-controller="reassign-form")
//     input[type=radio name=mode] (data-action="reassign-form#switchMode")
//     div(data-reassign-form-target="existingPanel")
//       input(data-reassign-form-target="searchInput" data-action="input->reassign-form#search")
//       input[type=hidden name=target_id] (data-reassign-form-target="targetId")
//       div(data-reassign-form-target="results")
//     div(data-reassign-form-target="newPanel")
export default class extends Controller {
  static targets = ["existingPanel", "newPanel", "searchInput", "targetId", "results"]
  static values = { searchUrl: String }

  connect() {
    this.switchMode()
  }

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

  search() {
    clearTimeout(this.timer)
    const q = this.searchInputTarget.value.trim()
    this.targetIdTarget.value = "" // sélection invalidée tant qu'on retape
    if (q.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }
    this.timer = setTimeout(() => this.runSearch(q), 200)
  }

  async runSearch(q) {
    try {
      const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, {
        headers: { Accept: "application/json" }
      })
      const customers = await response.json()
      this.renderResults(customers)
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
          `<button type="button" data-action="reassign-form#pick" data-id="${c.id}" data-label="${this.escape(c.name)}" class="block w-full text-left px-3 py-2 text-sm hover:bg-indigo-50">${this.escape(c.name)} <span class="text-gray-400">${this.escape(c.email || "")}</span></button>`
      )
      .join("")
  }

  pick(event) {
    const { id, label } = event.currentTarget.dataset
    this.targetIdTarget.value = id
    this.searchInputTarget.value = label
    this.resultsTarget.innerHTML = ""
  }

  escape(str) {
    const div = document.createElement("div")
    div.textContent = str ?? ""
    return div.innerHTML
  }
}
