import { Controller } from "@hotwired/stimulus"

// Stepper +/− pour les compteurs camping / hamacs de la grille de séjour.
// Rend visible un entier >= 0 sans ouvrir le clavier virtuel sur mobile.
// Un input[type=hidden] synchronisé transmet la valeur au formulaire.
export default class extends Controller {
  static targets = ["display", "input"]
  static values  = { min: { type: Number, default: 0 }, max: { type: Number, default: 99 } }

  get count() {
    return parseInt(this.inputTarget.value || "0", 10)
  }

  increment() {
    if (this.count < this.maxValue) this.set(this.count + 1)
  }

  decrement() {
    if (this.count > this.minValue) this.set(this.count - 1)
  }

  set(value) {
    const v = Math.max(this.minValue, Math.min(this.maxValue, value))
    this.inputTarget.value = String(v)
    this.displayTarget.textContent = String(v)
    this.updateDecBtn()
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  updateDecBtn() {
    const btn = this.element.querySelector("[data-action*=\"decrement\"]")
    if (!btn) return
    const atMin = this.count <= this.minValue
    btn.disabled = atMin
    btn.classList.toggle("opacity-30", atMin)
    btn.classList.toggle("cursor-not-allowed", atMin)
  }

  connect() {
    this.displayTarget.textContent = String(this.count)
    this.updateDecBtn()
  }
}
