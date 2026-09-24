import { Controller } from "@hotwired/stimulus"

// Les lignes du relevé de dépôt-vente (epic #248, phase 2).
//
// L'artisan tape ses ventes sur son téléphone : ajouter une ligne, en retirer
// une, et voir le total monter pendant qu'il tape. Le serveur recalcule tout de
// son côté — ici c'est du confort de saisie, pas une source de vérité.
//
// Une ligne déjà enregistrée ne se supprime pas du DOM : on coche son
// `_destroy` et on la cache, sinon Rails ne saurait pas qu'elle doit partir.
export default class extends Controller {
  static targets = ["rows", "template", "row", "gross", "commission", "net", "empty"]
  static values = { commissionPercent: Number }

  connect() {
    this.counter = 0
    this.refresh()
  }

  add(event) {
    event.preventDefault()

    const html = this.templateTarget.innerHTML.replaceAll("NEW_RECORD", this.nextIndex())
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.rowsTarget.lastElementChild?.querySelector("input")?.focus()
    this.refresh()
  }

  remove(event) {
    event.preventDefault()

    const row = event.target.closest("[data-public--consignment-lines-target='row']")
    if (!row) return

    const destroy = row.querySelector("input[name*='_destroy']")
    if (destroy) {
      destroy.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
    this.refresh()
  }

  // Un article choisi dans la liste (epic #359, phase 2) : son nom devient le
  // libellé, son prix du jour pré-remplit le prix — qui reste modifiable.
  // « Autre » rouvre le libellé libre.
  pick(event) {
    const row = event.target.closest("[data-public--consignment-lines-target='row']")
    if (!row) return

    const option = event.target.selectedOptions[0]
    const labelField = row.querySelector("[data-role='label-field']")
    const label = row.querySelector("[data-role='label']")
    const price = row.querySelector("[data-role='unit-price']")

    if (option && option.value) {
      if (label) label.value = option.dataset.name || ""
      if (price && option.dataset.priceCents) {
        price.value = (parseInt(option.dataset.priceCents, 10) / 100).toFixed(2)
      }
      if (labelField) labelField.hidden = true
    } else {
      if (label) label.value = ""
      if (labelField) labelField.hidden = false
      label?.focus()
    }
    this.refresh()
  }

  refresh() {
    let grossCents = 0

    this.rowTargets.forEach((row) => {
      if (row.hidden) return

      const quantity = parseInt(row.querySelector("[data-role='quantity']")?.value, 10) || 0
      const unit = this.toCents(row.querySelector("[data-role='unit-price']")?.value)
      const amount = quantity * unit

      const cell = row.querySelector("[data-role='amount']")
      if (cell) cell.textContent = this.format(amount)

      grossCents += amount
    })

    const commissionCents = Math.round((grossCents * this.commissionPercentValue) / 100)

    this.grossTarget.textContent = this.format(grossCents)
    if (this.hasCommissionTarget) this.commissionTarget.textContent = this.format(commissionCents)
    if (this.hasNetTarget) this.netTarget.textContent = this.format(grossCents - commissionCents)

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.rowTargets.some((row) => !row.hidden)
    }
  }

  // « 12,50 » comme « 12.50 » : au téléphone on tape la virgule.
  toCents(value) {
    const normalized = String(value ?? "").replace(",", ".")
    const euros = parseFloat(normalized)
    return Number.isNaN(euros) ? 0 : Math.round(euros * 100)
  }

  format(cents) {
    return new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR" }).format(cents / 100)
  }

  nextIndex() {
    this.counter += 1
    return `${Date.now()}${this.counter}`
  }
}
