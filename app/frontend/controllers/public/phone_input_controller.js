import { Controller } from "@hotwired/stimulus"
import intlTelInput from "intl-tel-input"
import { countryTranslations, interfaceTranslations } from "intl-tel-input/i18n/fr"
import "intl-tel-input/build/css/intlTelInput.css"

// Champ téléphone du funnel (étape Coordonnées) — intl-tel-input (MIT).
//
// Belgique par défaut, drapeau et indicatif choisis dans une liste cherchable,
// numéro mis en forme pendant la frappe. Les règles de numérotation (utils,
// ~250 Ko) ne se chargent qu'à l'ouverture de la page Coordonnées, jamais aux
// étapes précédentes.
//
// À l'envoi, le numéro part au format international lisible (« +32 470 12 34
// 56 ») : l'équipe le lit dans la fiche séjour et l'appelle tel quel, quel que
// soit le pays. Un numéro saisi mais invalide bloque l'envoi avec un message
// écrit, jamais une simple bordure rouge. Le champ reste FACULTATIF.
// Le serveur garde sa propre vérification (Reservations::PhoneFormat) : sans
// JavaScript, ce contrôleur ne fait rien et le champ redevient un input nu.
export default class extends Controller {
  static targets = ["input", "error"]

  connect() {
    this.iti = intlTelInput(this.inputTarget, {
      initialCountry: "be",
      countryOrder: ["be", "fr", "nl", "lu", "de"],
      i18n: { ...countryTranslations, ...interfaceTranslations },
      separateDialCode: false,
      strictMode: true,
      formatAsYouType: true,
      loadUtils: () => import("intl-tel-input/utils")
    })

    this.form = this.inputTarget.form
    this.onSubmit = this.validateOnSubmit.bind(this)
    this.form?.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit)
    this.iti?.destroy()
  }

  // Après une première erreur, le message s'efface dès que le numéro devient bon.
  check() {
    if (!this.errorShown) return
    if (this.isAcceptable()) this.clearError()
  }

  validateOnSubmit(event) {
    if (this.isAcceptable()) {
      this.normalize()
      return
    }
    event.preventDefault()
    event.stopImmediatePropagation()
    this.showError()
    this.inputTarget.focus()
  }

  isAcceptable() {
    const raw = this.inputTarget.value.trim()
    if (raw === "") return true
    // Utils pas encore chargés (réseau lent) : on laisse passer, le serveur
    // vérifie de son côté.
    if (!intlTelInput.utils) return true
    return this.iti.isValidNumberPrecise() === true
  }

  normalize() {
    const utils = intlTelInput.utils
    if (!utils || this.inputTarget.value.trim() === "") return
    this.inputTarget.value = this.iti.getNumber(utils.numberFormat.INTERNATIONAL)
  }

  showError() {
    this.errorShown = true
    this.inputTarget.setAttribute("aria-invalid", "true")
    if (this.hasErrorTarget) this.errorTarget.hidden = false
  }

  clearError() {
    this.errorShown = false
    this.inputTarget.removeAttribute("aria-invalid")
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
