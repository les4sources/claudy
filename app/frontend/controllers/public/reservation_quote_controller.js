import { Controller } from "@hotwired/stimulus"

// Recalcule le devis du funnel /reservation sans rechargement complet
// (AC-T2-10). À chaque modification d'un champ de composition, on soumet le
// formulaire de devis qui répond en Turbo Stream et remplace le panneau.
export default class extends Controller {
  static targets = ["form"]
  static values  = { url: String, contactUrl: String }

  refresh() {
    if (this.hasFormTarget) {
      this.formTarget.requestSubmit()
    }
  }

  // Sauvegarde le draft via quote (même token CSRF que le formulaire) puis
  // navigue vers l'étape coordonnées. Évite le problème per-form CSRF token
  // que poserait un formaction vers un endpoint différent.
  advance(event) {
    event.preventDefault()
    if (!this.hasFormTarget) {
      window.location.href = this.contactUrlValue
      return
    }
    const form = this.formTarget
    fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
    }).then(() => {
      window.location.href = this.contactUrlValue
    }).catch(() => {
      window.location.href = this.contactUrlValue
    })
  }
}
