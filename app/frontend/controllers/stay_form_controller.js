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
  static targets = [
    "existingPanel",
    "newPanel",
    "platform",
    "source",
    "roomsPanel",
    "roomsGroup",
    "spaceBillingPanel",
  ]

  connect() {
    this.toggleCustomer()
    this.toggleBookingMode()
    this.toggleSpaceBilling()
  }

  // Facturation espace (epic #81, Phase 6) : le sous-panneau n'apparaît que si au
  // moins une ligne d'espace porte un type sélectionné. Idempotent — rappelé au
  // connect pour restaurer l'état à l'édition (espace déjà présent → panneau
  // ouvert). Les champs restent dans le DOM même masqués : le serveur lit
  // `space_billing` normalement, et un panneau replié resoumet ses valeurs.
  toggleSpaceBilling() {
    if (!this.hasSpaceBillingPanelTarget) return
    // Lignes `halls` (journée sèche) OU grille date-par-date (`space_slots`) :
    // le panneau facturation s'ouvre dès qu'un espace est renseigné dans l'une
    // ou l'autre représentation.
    const anyKindSelected = Array.from(
      this.element.querySelectorAll('select[name^="stay[halls]"][name$="[kind]"]'),
    ).some((select) => select.value.trim() !== "")
    const anySlotSelected = Array.from(
      this.element.querySelectorAll('input[name^="stay[space_slots]"]'),
    ).some((input) => input.value.trim() !== "")
    this.spaceBillingPanelTarget.classList.toggle("hidden", !(anyKindSelected || anySlotSelected))
  }

  // Mode d'occupation (epic #81, Phase 5) : gîte entier / chambres seules. En mode
  // chambres, on révèle le panneau des chambres (et le bon groupe de gîte) ; sinon
  // on le masque. Idempotent — rappelé au connect pour restaurer l'état à l'édition.
  toggleBookingMode() {
    const rooms = this.bookingMode() === "rooms"
    if (this.hasRoomsPanelTarget) this.roomsPanelTarget.classList.toggle("hidden", !rooms)
    this.syncRoomVisibility()
  }

  // N'affiche que le groupe de chambres du gîte sélectionné, et seulement en mode
  // chambres. Décoche les chambres des gîtes masqués pour ne pas soumettre des
  // chambres d'un autre gîte (le serveur les filtrerait de toute façon).
  syncRoomVisibility() {
    if (!this.hasRoomsGroupTarget) return
    const rooms = this.bookingMode() === "rooms"
    const lodgingId = this.element.querySelector('[name="stay[lodging_id]"]')?.value || ""

    this.roomsGroupTargets.forEach((group) => {
      const match = rooms && group.dataset.lodgingId === lodgingId
      group.classList.toggle("hidden", !match)
      if (!match) {
        group.querySelectorAll('input[type="checkbox"]').forEach((cb) => (cb.checked = false))
      }
    })
  }

  bookingMode() {
    return (
      this.element.querySelector('input[name="stay[booking_type]"]:checked')?.value || "lodging"
    )
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
  //
  // `source`/`platform` sont désormais des groupes de RADIOS (issue parité
  // funnel) : `this.sourceTargets` / `this.platformTargets` listent les inputs.
  syncChannelFromPlatform() {
    if (!this.hasPlatformTarget || !this.hasSourceTarget) return

    const platform = this.checkedValue(this.platformTargets)
    const isOta = platform === "airbnb" || platform === "bookingdotcom"

    if (isOta) {
      this.setSourceIfPossible("ota")
    } else if (this.checkedValue(this.sourceTargets) === "ota") {
      this.setSourceIfPossible("manual")
    }
  }

  // Valeur du radio coché dans un groupe (ou "").
  checkedValue(radios) {
    return radios.find((r) => r.checked)?.value || ""
  }

  // Coche le radio canal `value` uniquement s'il existe (les options sont bornées
  // côté serveur à manual/ota + la source d'origine). No-op si déjà coché — sinon
  // on émet un `change` bouillonnant (pour le devis live et la cohérence).
  setSourceIfPossible(value) {
    const radio = this.sourceTargets.find((r) => r.value === value)
    if (!radio || radio.checked) return
    radio.checked = true
    radio.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
