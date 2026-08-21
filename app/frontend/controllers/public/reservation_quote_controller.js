import { Controller } from "@hotwired/stimulus"

// Recalcule le devis du funnel /reservation sans rechargement complet
// (AC-T2-10). À chaque modification d'un champ de composition, on soumet le
// formulaire de devis qui répond en Turbo Stream et remplace le panneau.
export default class extends Controller {
  static targets = ["form"]
  static values  = { url: String, nextUrl: String }

  // Le devis se recalcule TOUJOURS contre `urlValue`, jamais contre l'action du
  // formulaire : à l'étape composition les deux coïncident, mais à l'étape
  // activités le formulaire mène à l'étape suivante et doit continuer d'y mener
  // sans JS. On applique nous-mêmes le Turbo Stream renvoyé.
  refresh() {
    if (!this.hasFormTarget) return

    const form = this.formTarget
    fetch(this.urlValue, {
      method: "POST",
      body: new FormData(form),
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
      .then(response => response.text())
      .then(html => { if (html.trim() && window.Turbo) window.Turbo.renderStreamMessage(html) })
  }

  // Sauvegarde le draft via quote (même token CSRF que le formulaire) puis
  // navigue vers l'étape suivante (les activités — epic #55 Phase 4). Évite le
  // problème per-form CSRF token que poserait un formaction vers un autre endpoint.
  advance(event) {
    event.preventDefault()
    if (!this.hasFormTarget) {
      window.location.href = this.nextUrlValue
      return
    }
    const form = this.formTarget
    fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
    }).then(() => {
      window.location.href = this.nextUrlValue
    }).catch(() => {
      window.location.href = this.nextUrlValue
    })
  }
}
