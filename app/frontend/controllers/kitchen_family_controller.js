import { Controller } from "@hotwired/stimulus"

// Paramètres > Cuisine : une famille retirée de l'offre garde ses réglages,
// mais ils ne s'appliquent plus. On l'estompe pour que l'écran le dise.
export default class extends Controller {
  static targets = ["toggle", "fields"]

  connect() {
    this.refresh()
  }

  refresh() {
    const on = this.toggleTarget.checked
    this.fieldsTarget.classList.toggle("opacity-40", !on)
  }
}
