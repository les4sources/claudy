import { Controller } from "@hotwired/stimulus"

// Navigation nuit par nuit pour la grille Espaces. Scrolle le conteneur
// overflow-x par incréments de 4 colonnes (4 × 90px). Les cellules restent
// dans le DOM — les space_slot_controller de chaque cellule sont indépendants.
export default class extends Controller {
  static targets = ["scrollArea"]
  static SCROLL_AMOUNT = 4 * 90  // 4 colonnes × 90px

  prevNights() {
    this.scroll(-this.constructor.SCROLL_AMOUNT)
  }

  nextNights() {
    this.scroll(this.constructor.SCROLL_AMOUNT)
  }

  scroll(amount) {
    if (this.hasScrollAreaTarget) {
      this.scrollAreaTarget.scrollBy({ left: amount, behavior: "smooth" })
    }
  }
}
