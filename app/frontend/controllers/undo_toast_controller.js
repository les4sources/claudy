import { Controller } from "@hotwired/stimulus"

// Animated toast that disappears after a delay.
// Triggered by the archive turbo_stream that appends it to #flash_toasts.
export default class extends Controller {
  static values = { duration: { type: Number, default: 5000 } }

  connect() {
    requestAnimationFrame(() => this.element.classList.add("archive-toast--in"))
    this.timer = setTimeout(() => this.dismiss(), this.durationValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.element.classList.remove("archive-toast--in")
    this.element.classList.add("archive-toast--out")
    setTimeout(() => this.element.remove(), 250)
  }
}
