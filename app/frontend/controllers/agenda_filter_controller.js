import { Controller } from "@hotwired/stimulus"

// Filtres de l'agenda en rubans (nouvelle interface, Michael 2026-10-24) :
// Tout / Hébergements / Salles / Activités / Repas. Le choix pose
// `data-agenda-filter` sur la grille ; la feuille de style estompe les bandes
// d'une autre sorte (`data-kind`). Rien n'est rechargé, rien n'est retiré du
// DOM : une bande estompée reste lisible et cliquable.
//
// Le dernier filtre est gardé dans le navigateur, par confort seulement.
const KEY = "agenda-filter"
const KINDS = ["all", "lodging", "room", "activity", "meal"]

export default class extends Controller {
  static targets = ["button", "grid"]

  connect() {
    let kind = "all"
    try { kind = window.localStorage.getItem(KEY) || "all" } catch (_) { /* stockage indisponible */ }
    this.apply(KINDS.includes(kind) ? kind : "all")
  }

  pick(event) {
    const kind = event.currentTarget.dataset.kind
    this.apply(kind)
    try { window.localStorage.setItem(KEY, kind) } catch (_) { /* stockage indisponible */ }
  }

  apply(kind) {
    this.gridTargets.forEach((grid) => { grid.dataset.agendaFilter = kind })
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.kind === kind))
    })
  }
}
