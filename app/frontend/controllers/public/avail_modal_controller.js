import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "modal"]

  open() {
    this.overlayTarget.classList.remove("hidden")
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
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
