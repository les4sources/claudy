import { Controller } from "@hotwired/stimulus"

// Drawer devis du funnel /reservation. La barre récap sticky (toujours visible)
// ouvre ce panneau à la demande, à toutes les étapes. Desktop : slide-over
// depuis la droite (~28rem). Mobile : bottom-sheet (max-h 80vh, scrollable).
// L'état ouvert/fermé passe par `openValue` (data-…-open-value) — la bascule des
// classes de transform se fait dans render(), déclenché par openValueChanged().
export default class extends Controller {
  static targets = ["overlay", "panel"]
  static values  = { open: Boolean }

  connect() {
    // Assure un état visuel cohérent au montage (draft rechargé, Turbo, etc.).
    this.render()
  }

  open() {
    this.previouslyFocused = document.activeElement
    this.openValue = true
  }

  close() {
    this.openValue = false
  }

  // Esc n'agit que si le drawer est ouvert (câblé en keydown.esc@window).
  closeOnEsc() {
    if (this.openValue) this.close()
  }

  openValueChanged() {
    this.render()
  }

  render() {
    if (!this.hasPanelTarget || !this.hasOverlayTarget) return

    if (this.openValue) {
      this.panelTarget.classList.remove("translate-y-full", "sm:translate-x-full")
      this.panelTarget.classList.add("translate-y-0", "sm:translate-x-0")
      this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
      document.body.classList.add("overflow-hidden")
      this.panelTarget.focus()
    } else {
      this.panelTarget.classList.add("translate-y-full", "sm:translate-x-full")
      this.panelTarget.classList.remove("translate-y-0", "sm:translate-x-0")
      this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
      document.body.classList.remove("overflow-hidden")
      if (this.previouslyFocused && this.previouslyFocused.focus) {
        this.previouslyFocused.focus()
        this.previouslyFocused = null
      }
    }
  }
}
