import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = []

  submit() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.element.requestSubmit()
    }, 250)
  }
}
