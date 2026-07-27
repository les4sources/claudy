import { Controller } from "@hotwired/stimulus"

// Recharge les grilles de composition (hébergement + espaces + camping/van/
// hamacs) quand les dates du séjour changent : les colonnes doivent suivre les
// nuits réelles. Usage : contrôleur sur le form, action `change->stay-grids#reload`
// sur les champs de dates.
//
// On POSTe la composition COMPLÈTE du form (même corps que stay-quote) vers
// stays#compose_grids, qui répond en Turbo Stream et remplace le frame
// `stay_compose_grids`. Avant, on se contentait de repointer `frame.src` avec les
// deux dates : le serveur rebâtissait un Draft vide et le rechargement EFFAÇAIT
// toute la saisie du frame — tentes, vans, hamacs, nuits de gîte, grille espaces,
// note « précision du besoin » (bug remonté par Michael 2026-07-27).
export default class extends Controller {
  static values = { url: String, excludeStayId: String }

  reload() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.refresh(), 150)
  }

  async refresh() {
    const form = this.element
    // Une date effacée ne doit RIEN recharger : le serveur rendrait les
    // compteurs de repli (pas de fenêtre de nuits) et la grille affichée —
    // donc la saisie — disparaîtrait de l'écran pour rien.
    const arrival = form.querySelector('[name="stay[arrival_date]"]')?.value
    const departure = form.querySelector('[name="stay[departure_date]"]')?.value
    if (!arrival || !departure) return

    const body = new FormData(form)
    // En ÉDITION le form porte `_method=patch` : embarqué dans le fetch, Rails
    // réécrirait POST /stays/compose_grids en PATCH → #update avec
    // id="compose_grids". Même garde que stay-quote.
    body.delete("_method")
    // Exclusion du séjour édité pour la dispo de la grille hébergement : sans
    // elle, un séjour confirmé voit ses PROPRES nuits marquées « occupé ».
    if (this.hasExcludeStayIdValue && this.excludeStayIdValue) {
      body.set("exclude_stay_id", this.excludeStayIdValue)
    }

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
      window.Turbo.renderStreamMessage(await response.text())
      // Le devis doit refléter la grille REMPLACÉE (nuits retirées / ajoutées) :
      // on redéclenche stay-quote depuis le form. `change->stay-grids#reload` est
      // posé sur les seuls champs de dates — aucune boucle possible.
      form.dispatchEvent(new Event("change", { bubbles: true }))
    } catch (_e) {
      // Silencieux : la grille reste sur ses colonnes précédentes.
    }
  }
}
