import { Controller } from "@hotwired/stimulus"

// Répartir une ligne de trésorerie en plusieurs parts (epic #288, phase 6).
//
// Un virement paie souvent plusieurs choses : une nuitée et le bar, une salle
// et un repas. Le formulaire d'affectation garde sa première part telle quelle
// — le cas simple ne demande aucun geste de plus — et « Ajouter une part »
// pose, sous elle, une part de plus avec son compte, son pôle, son entité et
// son montant. Tout part en une requête : le serveur enregistre toutes les
// parts ou aucune.
//
// Le reste se recalcule à la frappe. Quand les parts dépassent la ligne, le
// bouton se désactive et le dit : le serveur refuserait de toute façon, mais
// autant ne pas perdre ce qu'on vient de saisir.
export default class extends Controller {
  static targets = ["list", "template", "part", "amount", "summary", "reste", "submit"]
  static values = { remaining: Number }

  connect() {
    this.index = 0
    this.recompute()
  }

  add(event) {
    event.preventDefault()
    const reste = this.resteCents()
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", `${Date.now()}${this.index++}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)

    const part = this.partTargets[this.partTargets.length - 1]
    const montant = part.querySelector("[data-allocation-parts-target~='amount']")
    // La nouvelle part propose ce qui reste : c'est presque toujours ce qu'on
    // vient y mettre.
    if (montant && this.sameSign(reste)) montant.value = this.format(reste)
    this.recompute()
    part.querySelector("input[type='text'], select")?.focus()
  }

  remove(event) {
    event.preventDefault()
    event.currentTarget.closest("[data-allocation-parts-target~='part']")?.remove()
    this.recompute()
  }

  recompute() {
    const avecParts = this.partTargets.length > 0
    this.summaryTarget.classList.toggle("hidden", !avecParts)
    if (!avecParts) {
      this.submitTarget.disabled = false
      return
    }

    const reste = this.resteCents()
    const depasse = Math.abs(this.saisiCents()) > Math.abs(this.remainingValue) || (reste !== 0 && !this.sameSign(reste))
    this.resteTarget.textContent = depasse
      ? `les parts dépassent la ligne de ${this.format(Math.abs(this.saisiCents()) - Math.abs(this.remainingValue))} €`
      : `reste ${this.format(reste)} € à affecter`
    this.resteTarget.classList.toggle("text-red-700", depasse)
    this.resteTarget.classList.toggle("text-amber-700", !depasse && reste !== 0)
    this.resteTarget.classList.toggle("text-forest", !depasse && reste === 0)
    this.submitTarget.disabled = depasse
  }

  // -- calculs, en centimes pour ne jamais additionner des flottants --------

  saisiCents() {
    return this.amountTargets.reduce((total, input) => total + this.parse(input.value), 0)
  }

  resteCents() {
    return this.remainingValue - this.saisiCents()
  }

  sameSign(cents) {
    return cents !== 0 && (cents > 0) === (this.remainingValue > 0)
  }

  // « 12,50 », « 12.50 », « -1 200,00 » : ce que les gens tapent.
  parse(texte) {
    const propre = String(texte || "").replace(/\s/g, "").replace(",", ".")
    const valeur = Number.parseFloat(propre)
    return Number.isFinite(valeur) ? Math.round(valeur * 100) : 0
  }

  format(cents) {
    return (cents / 100).toFixed(2).replace(".", ",")
  }
}
