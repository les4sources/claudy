import { Controller } from "@hotwired/stimulus"

// Modale de détails d'un séjour. Le lien "Détails" porte l'URL du séjour ;
// au clic on récupère le fragment HTML (rendu sans layout) et on l'injecte
// dans la modale, puis on l'ouvre. Approche fetch+inject, robuste y compris
// pour un <dialog> en top-layer (où le rendu auto Turbo Frame est capricieux).
//
// Usage:
//   div(data-controller="stay-details")
//     a(href=stay_path(stay) data-action="stay-details#open")
//     dialog(data-stay-details-target="dialog")
//       div(data-stay-details-target="content")
export default class extends Controller {
  static targets = ["dialog", "content"]

  connect() {
    // Hygiène cache Turbo (bug « back navigateur → modale morte ») : le
    // snapshot mis en cache ne doit jamais contenir un <dialog> ouvert —
    // sinon la page restaurée porte un dialog dans un état incohérent et
    // `showModal()` lève une InvalidStateError au clic suivant.
    this.beforeCache = () => { if (this.dialogTarget.open) this.dialogTarget.close() }
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.reopenFromUrl()
  }

  // Retour de l'édition (Michael, 2026-10-18) : le formulaire ouvert depuis la
  // modale revient ici avec `?open_stay=<id>`. On rouvre la modale de ce séjour
  // et on retire le paramètre de l'URL : ni un rechargement ni un retour
  // navigateur ne la rouvriront. Le premier contrôleur de la page qui le lit
  // le consomme, les autres ne le voient plus.
  //
  // Jamais sur un aperçu Turbo (snapshot affiché avant la vraie réponse) : la
  // modale ouverte là serait aussitôt écrasée par le vrai rendu, paramètre
  // déjà consommé. L'URL est réécrite par l'historique de Turbo pour que son
  // cache ne range pas la page sous l'adresse avec `open_stay`.
  reopenFromUrl() {
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    const url = new URL(window.location.href)
    const id = url.searchParams.get("open_stay")
    if (!/^\d+$/.test(id || "")) return

    url.searchParams.delete("open_stay")
    const turboHistory = window.Turbo?.session?.history
    if (turboHistory) {
      turboHistory.replace(url, turboHistory.restorationIdentifier)
    } else {
      window.history.replaceState(window.history.state, "", url.href)
    }
    this.openUrl(`/stays/${id}`)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  async open(event) {
    event.preventDefault()
    await this.openUrl(event.currentTarget.href)
  }

  // Ouverture depuis une LIGNE de tableau (index Séjours, Michael 2026-07-26).
  // Une <tr> n'a pas de href : l'URL vient de `data-stay-url`.
  //
  // Le garde sur les éléments interactifs est le point important : la ligne
  // contient le lien client, le <select> de catégorie et le lien « Éditer ».
  // Sans lui, la modale volerait ces clics et le dropdown deviendrait
  // inutilisable. On ne réagit donc qu'aux clics sur le « vide » de la ligne.
  async openFromRow(event) {
    // Un élément interactif NICHÉ dans la ligne garde son comportement (le
    // <select> de catégorie, le lien « Éditer »). Mais s'il PORTE lui-même
    // l'action — cas du bouton qui affiche le nom du client — c'est bien la
    // modale qu'on veut : d'où la comparaison avec `currentTarget`.
    const interactive = event.target.closest("a, button, select, input, label, [data-row-modal-ignore]")
    if (interactive && interactive !== event.currentTarget) return

    const url = event.currentTarget.dataset.stayUrl
    if (!url) return

    event.preventDefault()
    await this.openUrl(url)
  }

  async openUrl(base) {
    // `modal=1` : demande le FRAGMENT sans layout — la navigation directe vers
    // la même URL rend désormais la fiche séjour pleine page.
    const url = base + (base.includes("?") ? "&" : "?") + "modal=1"
    this.contentTarget.innerHTML = '<div class="px-6 py-8 text-center text-sm text-gray-500">Chargement…</div>'
    // Défensif : sur une page restaurée du cache, le dialog peut déjà être
    // marqué ouvert — on le referme avant de le rouvrir proprement.
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.dialogTarget.showModal()
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      this.contentTarget.innerHTML = await response.text()
      this.addReturnToEditLinks()
    } catch (_e) {
      this.contentTarget.innerHTML = '<div class="px-6 py-8 text-center text-sm text-red-600">Erreur de chargement.</div>'
    }
  }

  // Les liens vers le formulaire d'édition de la fiche emportent l'adresse de
  // la page SOUS la modale (le fragment ne la connaît pas), avec `open_stay` :
  // enregistrer ou annuler ramène ici, modale rouverte
  // (cf. StaysController#stay_return_path).
  addReturnToEditLinks() {
    this.contentTarget.querySelectorAll("a[href]").forEach((link) => {
      const href = new URL(link.href, window.location.origin)
      const match = href.pathname.match(/^\/stays\/(\d+)\/edit$/)
      if (!match) return

      const back = new URL(window.location.href)
      back.searchParams.set("open_stay", match[1])
      href.searchParams.set("return_to", back.pathname + back.search)
      link.setAttribute("href", href.pathname + href.search)
    })
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }
}
