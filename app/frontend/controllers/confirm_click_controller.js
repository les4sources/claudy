import { Controller } from "@hotwired/stimulus"

// Two-click confirmation for a form submit button (generic, reusable).
//
// `button_to` renders a <form> wrapping a <button>, so we hook the controller
// on the FORM and intercept its `submit` event (more reliable than the click):
// the first submit is prevented and the button morphs into a confirmation
// label with an alert (red) style, keeping its size stable to avoid layout
// shift. A second submit within the window lets the real submission proceed.
// Escape, a click/focus outside the form, or a timeout restores the button.
//
// Usage (Slim / button_to):
//   = button_to "Confirmer le séjour", path, method: :patch,
//       form: { data: { controller: "confirm-click",
//                       action: "submit->confirm-click#confirm",
//                       "confirm-click-label-value": "Êtes-vous sûr·e ?" } },
//       data: { "confirm-click-target": "button" }
//
// All state is instance-scoped (no globals), so multiple instances — including
// one injected dynamically into the calendar modal — coexist safely.
export default class extends Controller {
  static targets = ["button"]
  static values = {
    label: { type: String, default: "Confirmer ?" },
    delay: { type: Number, default: 4000 }
  }

  connect() {
    this.armed = false
    this.timer = null
    this.onKeydown = null
    this.onOutside = null
  }

  disconnect() {
    this.restore()
  }

  // Intercepts the form submit. First submit arms the confirmation; a second
  // submit while armed is allowed through untouched.
  confirm(event) {
    if (this.armed) {
      this.clearTimer()
      this.detachOutsideListeners()
      this.armed = false
      return
    }

    event.preventDefault()
    this.arm()
  }

  arm() {
    const button = this.buttonElement()
    if (!button) return

    this.armed = true
    this.originalHtml = button.innerHTML
    // Freeze the current width so the shorter confirm label doesn't shrink the
    // button and shift the surrounding layout.
    button.style.minWidth = `${button.offsetWidth}px`
    button.style.textAlign = "center"
    button.textContent = this.labelValue
    this.applyAlertStyle(button)

    this.timer = setTimeout(() => this.restore(), this.delayValue)

    this.onKeydown = (event) => {
      if (event.key === "Escape") this.restore()
    }
    this.onOutside = (event) => {
      if (!this.element.contains(event.target)) this.restore()
    }
    document.addEventListener("keydown", this.onKeydown)
    // Capture phase so an outside click restores before it does anything else.
    document.addEventListener("click", this.onOutside, true)
  }

  // Restores the button to its initial label and style.
  restore() {
    this.clearTimer()
    this.detachOutsideListeners()

    if (this.armed) {
      const button = this.buttonElement()
      if (button) {
        button.innerHTML = this.originalHtml
        button.style.minWidth = ""
        button.style.textAlign = ""
        this.removeAlertStyle(button)
      }
    }
    this.armed = false
  }

  // Inline styles (not Tailwind classes) so the alert look is guaranteed
  // regardless of JIT purging, and overrides the button's own bg/border.
  applyAlertStyle(button) {
    button.style.backgroundColor = "#dc2626" // red-600
    button.style.borderColor = "#dc2626"
    button.style.color = "#ffffff"
  }

  removeAlertStyle(button) {
    button.style.backgroundColor = ""
    button.style.borderColor = ""
    button.style.color = ""
  }

  buttonElement() {
    if (this.hasButtonTarget) return this.buttonTarget
    return this.element.querySelector("button")
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  detachOutsideListeners() {
    if (this.onKeydown) document.removeEventListener("keydown", this.onKeydown)
    if (this.onOutside) document.removeEventListener("click", this.onOutside, true)
    this.onKeydown = null
    this.onOutside = null
  }
}
