import { Controller } from "@hotwired/stimulus"

// Recharge le frame des grilles de composition (espaces + camping/van) quand
// les dates du séjour changent : les colonnes doivent suivre les nuits réelles.
// Usage : contrôleur sur le form, action `change->stay-grids#reload` sur les
// champs de dates. Le frame `stay_compose_grids` pointe stays#compose_grids.
export default class extends Controller {
  static values = { url: String }

  reload() {
    const frame = document.getElementById("stay_compose_grids")
    if (!frame) return
    const arrival = this.element.querySelector('[name="stay[arrival_date]"]')?.value
    const departure = this.element.querySelector('[name="stay[departure_date]"]')?.value
    const url = new URL(this.urlValue, window.location.origin)
    if (arrival) url.searchParams.set("arrival_date", arrival)
    if (departure) url.searchParams.set("departure_date", departure)
    frame.src = url.toString()
  }
}
