import { Controller } from "@hotwired/stimulus"

// Les blocs de prestation du formulaire de cuisine (issue #265).
//
// Le « + » clone un gabarit inerte gardé dans un <template> : rien de ce qu'il
// contient n'est soumis ni connecté à Stimulus tant qu'il n'est pas dans le
// document. Le clonage remplace le jeton d'index par un compteur qui ne
// redescend jamais — après un retrait, les index sautent (0, 2, 3) et c'est
// voulu : deux blocs ne doivent jamais se retrouver avec le même `name`, sinon
// Rails ne garde que le dernier et un bloc entier disparaît sans un mot.
//
// Le total général somme ce que chaque grille a déjà calculé pour elle-même :
// c'est le contrôleur `meal-grid` qui sait ce qu'un bloc coûte, remise de
// formule comprise.
export default class extends Controller {
  static targets = ["list", "template", "block", "label", "removeButton", "total"]

  connect() {
    this.nextIndex = this.blockTargets.length
    this.onGridTotal = () => this.refreshTotal()
    this.element.addEventListener("meal-grid:total", this.onGridTotal)
    this.renumber()
  }

  disconnect() {
    this.element.removeEventListener("meal-grid:total", this.onGridTotal)
  }

  add() {
    const index = this.nextIndex++
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", String(index))

    const holder = document.createElement("div")
    holder.innerHTML = html
    const block = holder.firstElementChild
    this.listTarget.appendChild(block)

    this.renumber()
    block.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  remove(event) {
    const block = event.currentTarget.closest("[data-meal-prestations-target='block']")
    if (!block) return

    block.remove()
    this.renumber()
    this.refreshTotal()
  }

  // Le numéro AFFICHÉ suit la position, pas l'index des `name` : « Prestation 3 »
  // doit être la troisième du formulaire même si son index est 5.
  renumber() {
    const blocks = this.blockTargets
    blocks.forEach((block, position) => {
      const label = block.querySelector("[data-meal-prestations-target='label']")
      if (label) label.textContent = `Prestation ${position + 1}`

      const remove = block.querySelector("[data-meal-prestations-target='removeButton']")
      // Le premier bloc ne se retire pas : un formulaire sans prestation n'a
      // rien à enregistrer.
      if (remove) remove.classList.toggle("hidden", blocks.length < 2)
    })

    this.refreshTotal()
  }

  refreshTotal() {
    if (!this.hasTotalTarget) return

    const cents = this.blockTargets.reduce(
      (sum, block) => sum + (parseInt(block.dataset.totalCents, 10) || 0),
      0
    )

    if (cents === 0) {
      this.totalTarget.textContent = ""
      return
    }

    this.totalTarget.textContent = `Total : ${(cents / 100).toFixed(2).replace(".", ",")} €`
  }
}
