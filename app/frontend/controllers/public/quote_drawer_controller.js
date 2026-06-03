import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "panel"]

  open() {
    this.panelTarget.classList.remove("translate-x-full")
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
    document.body.classList.remove("overflow-hidden")
  }
}
