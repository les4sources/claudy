import { Controller } from "@hotwired/stimulus"

// « Avez-vous besoin d'une facture ? » (étape Coordonnées, Michael 2026-10-03).
//
// « Oui » déplie les coordonnées de facturation et rend leurs champs
// obligatoires ; « Non » les replie et lève l'obligation (les valeurs restent,
// ignorées par le serveur). Le numéro de TVA est obligatoire aussi, sauf si
// la case « Sans numéro de TVA » est cochée : le champ est alors grisé et
// vidé de son obligation. Le numéro est contrôlé dans le navigateur
// sur son FORMAT seulement, avec les mêmes règles que
// Reservations::VatNumber ; VIES n'est interrogé que côté serveur.
//
// Sans JavaScript, le bloc s'affiche si la case était déjà cochée et le
// serveur fait tout le contrôle.
const PATTERNS = {
  AT: /^U\d{8}$/, BE: /^[01]\d{9}$/, BG: /^\d{9,10}$/, CY: /^\d{8}[A-Z]$/,
  CZ: /^\d{8,10}$/, DE: /^\d{9}$/, DK: /^\d{8}$/, EE: /^\d{9}$/, EL: /^\d{9}$/,
  ES: /^[A-Z0-9]\d{7}[A-Z0-9]$/, FI: /^\d{8}$/, FR: /^[A-HJ-NP-Z0-9]{2}\d{9}$/,
  HR: /^\d{11}$/, HU: /^\d{8}$/, IE: /^(\d{7}[A-W][A-I]?|\d[A-Z+*]\d{5}[A-W])$/,
  IT: /^\d{11}$/, LT: /^(\d{9}|\d{12})$/, LU: /^\d{8}$/, LV: /^\d{11}$/,
  MT: /^\d{8}$/, NL: /^\d{9}B\d{2}$/, PL: /^\d{10}$/, PT: /^\d{9}$/,
  RO: /^\d{2,10}$/, SE: /^\d{12}$/, SI: /^\d{8}$/, SK: /^\d{10}$/,
  CH: /^E\d{9}(MWST|TVA|IVA)?$/, GB: /^(\d{9}|\d{12})$/
}

export function normalizeVat(raw, country = "BE") {
  let vat = String(raw || "").toUpperCase().replace(/[^A-Z0-9+*]/g, "")
  if (vat === "") return ""
  const prefix = country === "GR" ? "EL" : (country || "BE")
  if (/^\d/.test(vat)) vat = prefix + vat
  vat = vat.replace(/^GR/, "EL")
  if (/^BE\d{9}$/.test(vat)) vat = "BE0" + vat.slice(2)
  return vat
}

export function isValidVat(vat) {
  const prefix = vat.slice(0, 2)
  const body = vat.slice(2)
  const pattern = PATTERNS[prefix]
  if (!pattern || !pattern.test(body)) return false
  if (prefix === "BE") return 97 - (parseInt(body.slice(0, 8), 10) % 97) === parseInt(body.slice(8), 10)
  return true
}

export default class extends Controller {
  static targets = ["fields", "vat", "vatError", "country", "noVat"]

  connect() {
    this.form = this.element.closest("form")
    this.onSubmit = this.validateOnSubmit.bind(this)
    this.form?.addEventListener("submit", this.onSubmit)
    // Une erreur rendue par le serveur (VIES) s'efface aussi à la correction.
    this.errorShown = !this.vatErrorTarget.hidden
    this.toggle()
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit)
  }

  get requested() {
    return this.element.querySelector('input[name="reservation[invoice_requested]"]:checked')?.value === "1"
  }

  toggle() {
    const on = this.requested
    this.fieldsTarget.hidden = !on
    this.element.querySelectorAll("[data-public--billing-required]").forEach((input) => {
      input.required = on
    })
    const noVat = this.hasNoVatTarget && this.noVatTarget.checked
    this.vatTarget.disabled = noVat
    this.vatTarget.required = on && !noVat
    if (noVat && this.errorShown) this.clearError()
  }

  get noVat() {
    return this.hasNoVatTarget && this.noVatTarget.checked
  }

  // Après une première erreur, le message s'efface dès que le numéro est bon.
  checkVat() {
    if (!this.errorShown) return
    if (this.vatAcceptable()) this.clearError()
  }

  vatAcceptable() {
    if (this.noVat) return true
    const raw = this.vatTarget.value.trim()
    // Vide : c'est l'attribut `required` qui le signale, pas ce message.
    if (raw === "") return true
    return isValidVat(normalizeVat(raw, this.hasCountryTarget ? this.countryTarget.value : "BE"))
  }

  validateOnSubmit(event) {
    if (!this.requested || this.vatAcceptable()) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.errorShown = true
    this.vatTarget.setAttribute("aria-invalid", "true")
    this.vatErrorTarget.textContent = "Ce numéro de TVA n'a pas le bon format (ex. : BE0123456789)."
    this.vatErrorTarget.hidden = false
    this.vatTarget.focus()
  }

  clearError() {
    this.errorShown = false
    this.vatTarget.removeAttribute("aria-invalid")
    this.vatErrorTarget.hidden = true
  }
}
