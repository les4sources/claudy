import { Controller } from "@hotwired/stimulus"

// Tiroir du jour choisi, en bas de l'agenda en rubans (Michael 2026-11-12).
// Le calendrier prend toute la largeur ; le jour vit dans un tiroir collé au
// bas de l'écran. Replié, seule sa barre se voit (date, chambres libres ce
// soir, qui veille). Il s'ouvre d'un clic sur la barre ou quand un jour de la
// grille charge le cadre `agenda_day`, et se ferme par la barre ou Échap.
// L'état tient dans la classe `is-open` ; le contenu du cadre, remplacé à
// chaque jour, reprend l'état par `sync`.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.sync()
  }

  // Un nouveau jour vient d'être chargé dans le cadre.
  open() {
    this.element.classList.add("is-open")
    this.sync()
  }

  close() {
    if (!this.element.classList.contains("is-open")) return
    // Échap ferme d'abord une fenêtre ouverte par-dessus, pas le tiroir.
    if (document.querySelector("dialog[open], turbo-frame#modal [role='dialog']")) return
    this.element.classList.remove("is-open")
    this.sync()
  }

  // Clic sur la barre : les liens (veilleur…) gardent leur rôle.
  toggleFromBar(event) {
    if (event.target.closest("a")) return
    this.element.classList.toggle("is-open")
    this.sync()
  }

  toggleTargetConnected() {
    this.sync()
  }

  sync() {
    const open = this.element.classList.contains("is-open")
    this.toggleTargets.forEach((button) => {
      button.setAttribute("aria-expanded", String(open))
      button.setAttribute("aria-label", open ? "Replier le détail du jour" : "Montrer le détail du jour")
    })
  }
}
