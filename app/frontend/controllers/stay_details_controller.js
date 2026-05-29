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

  async open(event) {
    event.preventDefault()
    const url = event.currentTarget.href
    this.contentTarget.innerHTML = '<div class="px-6 py-8 text-center text-sm text-gray-500">Chargement…</div>'
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
