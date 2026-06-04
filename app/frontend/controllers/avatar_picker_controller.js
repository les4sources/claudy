import { Controller } from "@hotwired/stimulus"

// Clickable-avatar person picker. Drives hidden form inputs from the selected
// avatars. Works in two modes:
//   - single: one selection, writes a single hidden input (e.g. carrier_id)
//   - multi:  many selections, writes one hidden input per selected id plus an
//             empty sentinel so deselecting all still clears the association.
//
// Markup contract (see shared/_avatar_picker):
//   data-controller="avatar-picker"
//   data-avatar-picker-mode-value="single|multi"
//   data-avatar-picker-name-value="agenda_item[carrier_id]"  // or "...[human_ids][]"
//   each option: data-avatar-picker-target="option" data-human-id=ID data-selected="true|false"
//   a hidden container: data-avatar-picker-target="inputs"
export default class extends Controller {
  static targets = ["option", "inputs"]
  static values = {
    mode: { type: String, default: "multi" },
    name: String,
  }

  connect() {
    this._syncInputs()
  }

  toggle(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const wasSelected = btn.dataset.selected === "true"

    if (this.modeValue === "single") {
      this.optionTargets.forEach((o) => this._setSelected(o, false))
      this._setSelected(btn, !wasSelected)
    } else {
      this._setSelected(btn, !wasSelected)
    }
    this._syncInputs()
  }

  _setSelected(btn, on) {
    btn.dataset.selected = on ? "true" : "false"
    btn.classList.toggle("ring-2", on)
    btn.classList.toggle("ring-emerald-500", on)
    btn.classList.toggle("ring-offset-2", on)
    btn.classList.toggle("opacity-40", !on)
  }

  _syncInputs() {
    this.inputsTarget.replaceChildren()
    const selected = this.optionTargets
      .filter((o) => o.dataset.selected === "true")
      .map((o) => o.dataset.humanId)

    if (this.modeValue === "single") {
      this.inputsTarget.appendChild(this._hidden(this.nameValue, selected[0] || ""))
    } else {
      // Empty sentinel ensures the param is always submitted.
      this.inputsTarget.appendChild(this._hidden(this.nameValue, ""))
      selected.forEach((id) => this.inputsTarget.appendChild(this._hidden(this.nameValue, id)))
    }
  }

  _hidden(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    return input
  }
}
