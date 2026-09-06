import { Controller } from "@hotwired/stimulus"

// Produits du buffet : l'unité est commune au produit, les quantités sont par
// type. On répète l'unité choisie à côté de chaque champ pour qu'on sache ce
// qu'on tape sans remonter au sélecteur.
export default class extends Controller {
  static targets = ["select", "suffix"]

  connect() {
    this.refresh()
  }

  refresh() {
    const label = this.selectTarget.value === "piece" ? "pièce(s)" : this.selectTarget.value
    this.suffixTargets.forEach((suffix) => { suffix.textContent = label })
  }
}
