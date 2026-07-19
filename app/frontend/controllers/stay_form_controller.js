import { Controller } from "@hotwired/stimulus"

// Formulaire CRUD Séjour admin (epic #66, Phase 1). Bascule client existant /
// nouveau client : seul le panneau actif est visible (les deux restent dans le
// DOM, le contrôleur ne soumet pas côté client — c'est `customer_mode` qui dit
// au serveur quel panneau lire).
//
// Usage (dans stays/_form) :
//   form(data-controller="stay-form")
//     input[type=radio name="stay[customer_mode]"] (data-action="change->stay-form#toggleCustomer")
//     div(data-stay-form-target="existingPanel")
//     div(data-stay-form-target="newPanel")
//     select[name="stay[platform]"] (data-stay-form-target="platform" data-action="change->stay-form#syncChannelFromPlatform")
//     select[name="stay[source]"]   (data-stay-form-target="source")
export default class extends Controller {
  static targets = ["existingPanel", "newPanel", "platform", "source"]

  connect() {
    this.toggleCustomer()
  }

  toggleCustomer() {
    const mode =
      this.element.querySelector('input[name="stay[customer_mode]"]:checked')?.value ||
      "existing"
    this.togglePanel(this.existingPanelTarget, mode === "existing")
    this.togglePanel(this.newPanelTarget, mode === "new")
  }

  togglePanel(panel, active) {
    if (!panel) return
    panel.classList.toggle("hidden", !active)
  }

  // Cohérence plateforme ↔ canal (epic #81, Phase 4). Choisir une plateforme OTA
  // (Airbnb / Booking.com) bascule automatiquement le canal sur « OTA ». Repasser
  // en « Réservation directe » (web) NE force le retour à « Saisie manuelle » QUE
  // si le canal était justement « ota » — on ne réécrit jamais un autre canal
  // (reservation / tally_legacy conservés en édition).
  syncChannelFromPlatform() {
    if (!this.hasPlatformTarget || !this.hasSourceTarget) return

    const isOta =
      this.platformTarget.value === "airbnb" ||
      this.platformTarget.value === "bookingdotcom"

    if (isOta) {
      this.setSourceIfPossible("ota")
    } else if (this.sourceTarget.value === "ota") {
      this.setSourceIfPossible("manual")
    }
  }

  // Positionne le <select> canal sur `value` uniquement si l'option existe (les
  // options sont bornées côté serveur à manual/ota + la source d'origine). No-op
  // si la valeur est déjà en place — évite tout événement superflu.
  setSourceIfPossible(value) {
    const hasOption = Array.from(this.sourceTarget.options).some((o) => o.value === value)
    if (!hasOption || this.sourceTarget.value === value) return
    this.sourceTarget.value = value
  }
}
