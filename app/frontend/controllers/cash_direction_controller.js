import { Controller } from "@hotwired/stimulus"

// Le formulaire de la feuille de caisse prend la couleur du sens de son motif
// (Michael, 2026-11-12) : un fond légèrement vert pour une entrée, légèrement
// rouge pour une sortie, neutre sans motif ou pour un motif « Les deux ».
// On voit d'un coup d'œil si la ligne va faire entrer ou sortir l'argent, avant
// de cliquer « Ajouter ».
//
// Le sens est porté par chaque <option> (`data-direction` = in / out / both).
// Le <select> reste la source de vérité : la liste cherchable y relaie chaque
// choix par un événement `change`, qu'on écoute ici.
//
// Usage :
//   div(data-controller="cash-direction"
//       data-cash-direction-in-class="…" data-cash-direction-out-class="…"
//       data-cash-direction-neutral-class="…"
//       data-action="change->cash-direction#refresh")
//     select(data-cash-direction-target="select") …
export default class extends Controller {
  static targets = ["select"]
  static classes = ["in", "out", "neutral"]

  connect() {
    this.refresh()
  }

  refresh() {
    const sens = this.selectTarget.selectedOptions[0]?.dataset.direction
    const choisi = sens === "in" ? "in" : sens === "out" ? "out" : "neutral"

    for (const cle of ["in", "out", "neutral"]) {
      const classes = this[`${cle}Classes`]
      if (cle === choisi) this.element.classList.add(...classes)
      else this.element.classList.remove(...classes)
    }
    this.element.dataset.direction = choisi
  }
}
