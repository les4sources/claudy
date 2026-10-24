import { Controller } from "@hotwired/stimulus"

// Menu « Plus » de la barre d'onglets (nouvelle interface, 2026-10-24) : un
// <dialog> natif, ouvert en feuille depuis le bas. Échap le ferme (natif), un
// toucher hors de la feuille aussi.
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.beforeCache = () => { if (this.dialogTarget.open) this.dialogTarget.close() }
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
