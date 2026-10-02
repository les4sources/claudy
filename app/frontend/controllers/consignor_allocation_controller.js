import { Controller } from "@hotwired/stimulus"

// Affecter un encaissement au compte artisanat (epic #359, phase 4) : le champ
// « Artisan » n'apparaît que lorsque ce compte est choisi. Ailleurs il n'a rien
// à dire, et le serveur l'ignore de toute façon.
export default class extends Controller {
  static targets = ["account", "field"]
  static values = { craftAccountId: Number }

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasAccountTarget || !this.hasFieldTarget) return

    const craft = Number(this.accountTarget.value) === this.craftAccountIdValue
    this.fieldTarget.classList.toggle("hidden", !craft)
  }
}
