import { Controller } from "@hotwired/stimulus"

// Recalcule le devis du funnel /reservation sans rechargement complet
// (AC-T2-10). À chaque modification d'un champ de composition, on soumet le
// formulaire de devis qui répond en Turbo Stream et remplace le panneau.
export default class extends Controller {
  static targets = ["form"]

  refresh() {
    if (this.hasFormTarget) {
      this.formTarget.requestSubmit()
    }
  }
}
