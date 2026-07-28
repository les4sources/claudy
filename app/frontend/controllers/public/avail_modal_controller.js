import { Controller } from "@hotwired/stimulus"

// Modale « Disponibilités » du funnel /reservation.
//
// Au-delà de l'ouverture/fermeture, ce contrôleur porte les trois obligations
// d'un vrai dialogue modal, qui manquaient toutes :
//   1. Escape ferme.
//   2. Le focus entre dans la modale à l'ouverture et n'en sort pas au Tab
//      (sans piège, on tabule dans la page derrière l'overlay — état sans issue
//      au clavier, puisque le bouton de fermeture n'est alors plus atteignable).
//   3. Le focus retourne sur l'élément qui a ouvert la modale à la fermeture,
//      pour ne pas rejeter l'utilisateur en haut du document.
const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  '[tabindex]:not([tabindex="-1"])'
].join(",")

export default class extends Controller {
  static targets = ["overlay", "modal"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    // Mémorise le déclencheur : c'est là que le focus doit revenir. `event` est
    // absent quand l'ouverture vient de l'évènement window `reservation:open-avail`.
    this.previouslyFocused =
      (event && event.currentTarget instanceof HTMLElement ? event.currentTarget : null) ||
      (document.activeElement instanceof HTMLElement ? document.activeElement : null)

    this.overlayTarget.classList.remove("hidden")
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")

    // Le focus va sur le panneau lui-même (tabindex="-1") plutôt que sur le
    // premier bouton : le lecteur d'écran annonce alors le titre du dialogue
    // avant son premier contrôle.
    this.modalTarget.focus()
  }

  close() {
    if (!this.isOpen) return

    this.overlayTarget.classList.add("hidden")
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")

    if (this.previouslyFocused && document.contains(this.previouslyFocused)) {
      this.previouslyFocused.focus()
    }
    this.previouslyFocused = null
  }

  get isOpen() {
    return this.hasModalTarget && !this.modalTarget.classList.contains("hidden")
  }

  handleKeydown(event) {
    if (!this.isOpen) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "Tab") this.trapFocus(event)
  }

  // Boucle le Tab à l'intérieur du panneau. Le calendrier interne pouvant être
  // remplacé à chaque navigation de mois, on relit les cibles à chaque frappe
  // plutôt que de les mémoriser à l'ouverture.
  trapFocus(event) {
    const focusables = Array.from(this.modalTarget.querySelectorAll(FOCUSABLE)).filter(
      (el) => el.offsetParent !== null || el === document.activeElement
    )
    if (focusables.length === 0) {
      event.preventDefault()
      this.modalTarget.focus()
      return
    }

    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    const active = document.activeElement

    if (event.shiftKey && (active === first || active === this.modalTarget)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  }

  // Navigation mois par mois — fetch manuel car Turbo Frame ne se met pas
  // à jour correctement lorsque le frame vit dans une modale fixed/hidden.
  async navigate(event) {
    event.preventDefault()
    const url = event.currentTarget.dataset.navUrl
    if (!url) return
    const frame = this.element.querySelector("#avail_cal")
    if (!frame) return
    try {
      const res = await fetch(url, { headers: { Accept: "text/html" } })
      const html = await res.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const newFrame = doc.getElementById("avail_cal")
      if (newFrame) frame.innerHTML = newFrame.innerHTML
    } catch (_e) {
      // navigation silently fails — user can retry
    }
  }
}
