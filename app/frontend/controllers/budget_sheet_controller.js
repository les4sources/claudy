import { Controller } from "@hotwired/stimulus"

// Le budget détaillé (étape 4 du redressement, 2026-10-18) : les totaux
// suivent la saisie, sans attendre l'enregistrement. On corrige un loyer, le
// résultat prévu du pôle et de l'entité bouge sous les yeux.
//
// Les cases parlent comme le serveur : « 1 200 », « 1 250,50 ». Une case
// illisible compte pour zéro ici ; c'est le serveur qui la refusera.
const FORMAT = new Intl.NumberFormat("fr-BE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 })

export default class extends Controller {
  static targets = ["amount", "revenue", "expense", "net", "groupNet"]

  recompute() {
    const totals = { revenue: 0, expense: 0 }
    const groups = {}

    this.amountTargets.forEach((input) => {
      const cents = this.parse(input.value)
      const kind = input.dataset.kind
      totals[kind] += cents
      const group = (groups[input.dataset.group] ||= { revenue: 0, expense: 0 })
      group[kind] += cents
    })

    this.show(this.revenueTarget, totals.revenue)
    this.show(this.expenseTarget, totals.expense)
    this.show(this.netTarget, totals.revenue - totals.expense, true)
    this.groupNetTargets.forEach((el) => {
      const group = groups[el.dataset.group] || { revenue: 0, expense: 0 }
      this.show(el, group.revenue - group.expense, true)
    })
  }

  parse(value) {
    const normalized = value.replace(/[\s  ]/g, "").replace(",", ".")
    const euros = Number.parseFloat(normalized)
    return Number.isFinite(euros) ? Math.round(euros * 100) : 0
  }

  show(el, cents, signed = false) {
    el.textContent = FORMAT.format(cents / 100)
    if (signed) {
      el.classList.toggle("text-red-700", cents < 0)
      el.classList.toggle("text-stone-900", cents >= 0)
    }
  }
}
