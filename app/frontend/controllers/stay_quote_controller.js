import { Controller } from "@hotwired/stimulus"

// Devis LIVE du form de composition Séjour admin (issue #73). À chaque
// changement de la composition (hébergement, espaces, camping, van, repas,
// activités, dates, occupants), poste le form à `stays/quote` qui répond en
// Turbo Stream et remplace le panneau « Devis (B2C) ». Réutilise le MÊME barème
// que le submit (PricingModel) — aucun nouveau calcul de prix.
//
// Dégradation gracieuse : sans JS, le devis reste rendu au submit (comportement
// historique). L'action est posée sur le form (les événements des champs
// remontent), avec un débounce pour ne pas poster à chaque frappe.
export default class extends Controller {
  static values = { url: String }

  check() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.refresh(), 300)
  }

  async refresh() {
    const form = this.element
    const body = new FormData(form)
    // Bug 2026-07-20 : en ÉDITION le form porte `_method=patch` — embarqué
    // dans le fetch, Rails réécrivait POST /stays/quote en PATCH → routé vers
    // #update avec id="quote" → 404 et devis figé. Le devis est toujours un
    // POST pur.
    body.delete("_method")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
      })
      if (!response.ok) return
      const stream = await response.text()
      window.Turbo.renderStreamMessage(stream)
    } catch (_e) {
      // Silencieux : le devis au submit reste la source de repli.
    }
  }
}
