import { Controller } from "@hotwired/stimulus"

// Vérification de disponibilité de l'hébergement en TEMPS RÉEL dans le form de
// composition Séjour admin (issue #77). À chaque changement d'hébergement ou de
// dates, interroge `GET stays/availability` (JSON { available: bool }) et met à
// jour un indicateur. INFORME sans bloquer : la checkbox « Forcer la
// disponibilité » reste la seule décision de blocage/forçage.
//
// Usage (dans stays/_form) :
//   form(data-controller="stay-form stay-availability"
//        data-stay-availability-url-value="<%= availability_stays_path %>")
//     select[name="stay[lodging_id]"]      (data-action="change->stay-availability#check")
//     input[name="stay[arrival_date]"]     (data-action="change->stay-availability#check")
//     input[name="stay[departure_date]"]   (data-action="change->stay-availability#check")
//     div(data-stay-availability-target="indicator")
export default class extends Controller {
  static targets = ["indicator"]
  static values = { url: String, excludeStayId: Number }

  connect() {
    this.check()
  }

  check() {
    // Débounce léger : évite une requête à chaque micro-changement.
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.fetchAvailability(), 250)
  }

  async fetchAvailability() {
    const lodgingId = this.fieldValue("stay[lodging_id]")
    const arrival = this.fieldValue("stay[arrival_date]")
    const departure = this.fieldValue("stay[departure_date]")

    if (!lodgingId || !arrival || !departure) {
      this.hide()
      return
    }

    const params = new URLSearchParams({
      lodging_id: lodgingId,
      arrival_date: arrival,
      departure_date: departure,
    })

    // Édition : exclure les chambres du séjour lui-même (pas d'auto-indispo).
    if (this.hasExcludeStayIdValue && this.excludeStayIdValue > 0) {
      params.set("exclude_stay_id", this.excludeStayIdValue)
    }

    // Mode chambres seules (epic #81, Phase 5) : la dispo porte sur les chambres
    // cochées. Sans chambre cochée, l'endpoint répond checkable:false → on masque.
    const bookingType =
      this.element.querySelector('input[name="stay[booking_type]"]:checked')?.value || "lodging"
    if (bookingType === "rooms") {
      params.set("booking_type", "rooms")
      this.checkedRoomIds().forEach((id) => params.append("room_ids[]", id))
    }

    try {
      const response = await fetch(`${this.urlValue}?${params}`, {
        headers: { Accept: "application/json" },
      })
      if (!response.ok) {
        this.hide()
        return
      }
      const data = await response.json()
      if (!data.checkable) {
        this.hide()
      } else if (data.available) {
        this.render(true, "Disponible à ces dates.")
      } else {
        this.render(false, "Indisponible à ces dates — cochez « Forcer la disponibilité » pour enregistrer malgré tout.")
      }
    } catch (_e) {
      this.hide()
    }
  }

  fieldValue(name) {
    return this.element.querySelector(`[name="${name}"]`)?.value?.trim() || ""
  }

  // Chambres cochées ET VISIBLES (les groupes masqués sont décochés par stay-form).
  checkedRoomIds() {
    return Array.from(
      this.element.querySelectorAll('input[name="stay[room_ids][]"]:checked')
    ).map((cb) => cb.value)
  }

  render(available, message) {
    if (!this.hasIndicatorTarget) return
    const el = this.indicatorTarget
    el.textContent = message
    el.classList.remove("hidden", "bg-green-50", "text-green-800", "bg-red-50", "text-red-800")
    el.classList.add(...(available ? ["bg-green-50", "text-green-800"] : ["bg-red-50", "text-red-800"]))
  }

  hide() {
    if (this.hasIndicatorTarget) this.indicatorTarget.classList.add("hidden")
  }
}
