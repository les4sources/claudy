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
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  async open(event) {
    event.preventDefault()
    // `modal=1` : demande le FRAGMENT sans layout — la navigation directe vers
    // la même URL rend désormais la fiche séjour pleine page.
    const base = event.currentTarget.href
    const url = base + (base.includes("?") ? "&" : "?") + "modal=1"
    this.contentTarget.innerHTML = '<div class="px-6 py-8 text-center text-sm text-gray-500">Chargement…</div>'
    // Défensif : sur une page restaurée du cache, le dialog peut déjà être
    // marqué ouvert — on le referme avant de le rouvrir proprement.
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.dialogTarget.showModal()
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } })
      this.contentTarget.innerHTML = await response.text()
    } catch (_e) {
      this.contentTarget.innerHTML = '<div class="px-6 py-8 text-center text-sm text-red-600">Erreur de chargement.</div>'
    }
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }
}
