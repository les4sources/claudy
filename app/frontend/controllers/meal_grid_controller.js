import { Controller } from "@hotwired/stimulus"

// Grille jours × services du formulaire de cuisine (issue #238).
//
// Trois services : les boutons de remplissage, la ligne « Goûter » qui
// n'apparaît que pour la famille « Repas », et le compteur qui annonce en
// direct ce que la demande va coûter — remise de formule comprise, parce que
// c'est le montant que le client verra.
//
// Issue #265 : une instance PAR BLOC de prestation. Le type, les convives et le
// prix se cherchent donc dans le bloc, jamais dans le formulaire — sinon la
// grille du bloc 2 lirait le type du bloc 1 et annoncerait un total faux. Les
// sélecteurs visent la FIN du `name` (`[kind]`, `[people]`, `[unit_price]`) :
// elle est la même que le champ s'appelle `meal_order[kind]` ou
// `prestations[3][kind]`.
export default class extends Controller {
  static targets = ["cell", "row", "counter"]
  static values = { rates: Object, trio: Number }

  connect() {
    // `blockScope`, pas `scope` : Stimulus définit déjà un getter `scope` sur
    // Controller, et l'écraser fait échouer la connexion en silence — la grille
    // reste à l'écran, inerte.
    this.blockScope =
      this.element.closest("[data-meal-prestations-target='block']") || this.element.closest("form")

    this.kindInputs = Array.from(this.blockScope.querySelectorAll('input[type="radio"][name$="[kind]"]'))
    this.peopleInput = this.blockScope.querySelector('input[name$="[people]"]')
    this.unitInput = this.blockScope.querySelector('input[name$="[unit_price]"]')

    this.onChange = () => this.syncFamily()
    this.kindInputs.forEach((input) => input.addEventListener("change", this.onChange))
    if (this.peopleInput) this.peopleInput.addEventListener("input", this.onChange)
    if (this.unitInput) this.unitInput.addEventListener("input", this.onChange)

    this.syncFamily()
  }

  disconnect() {
    this.kindInputs.forEach((input) => input.removeEventListener("change", this.onChange))
    if (this.peopleInput) this.peopleInput.removeEventListener("input", this.onChange)
    if (this.unitInput) this.unitInput.removeEventListener("input", this.onChange)
  }

  fill(event) {
    const mode = event.currentTarget.dataset.mode

    this.cellTargets.forEach((cell) => {
      if (cell.closest("tr").hidden) return
      const moment = cell.dataset.moment

      if (mode === "none") cell.checked = false
      else if (mode === "all" || mode === "trio") cell.checked = true
      else cell.checked = moment === mode
    })

    this.recount()
  }

  // La famille du type choisi décide si le goûter existe : buffet et apéro n'en
  // ont pas. Une case cochée sur une ligne qui disparaît est décochée — sinon
  // elle partirait au serveur sans que personne ne la voie.
  syncFamily() {
    const kind = this.kindInputs.find((input) => input.checked)?.value
    const hasGouter = kind === "repas"

    this.rowTargets.forEach((row) => {
      if (row.dataset.moment !== "gouter") return

      row.hidden = !hasGouter
      row.classList.toggle("hidden", !hasGouter)
      if (!hasGouter) {
        row.querySelectorAll('input[type="checkbox"]').forEach((cell) => { cell.checked = false })
      }
    })

    this.recount()
  }

  recount() {
    const checked = this.cellTargets.filter((cell) => cell.checked && !cell.closest("tr").hidden)
    const people = Math.max(parseInt(this.peopleInput?.value, 10) || 0, 0)

    if (checked.length === 0) {
      this.counterTarget.textContent = "Aucun service coché."
      this.publishTotal(0)
      return
    }

    const total = this.totalCents(checked, people)
    const euros = (total / 100).toFixed(2).replace(".", ",")
    const services = `${checked.length} service${checked.length > 1 ? "s" : ""}`
    const convives = `${people} convive${people > 1 ? "s" : ""}`

    this.counterTarget.textContent = `${services} · ${convives} · ${euros} €`
    this.publishTotal(total)
  }

  // Le bloc porte son total sur lui, puis prévient : c'est le contrôleur parent
  // qui somme, et il n'a pas à savoir comment une grille compte.
  publishTotal(cents) {
    if (this.blockScope) this.blockScope.dataset.totalCents = String(cents)

    this.element.dispatchEvent(
      new CustomEvent("meal-grid:total", { bubbles: true, detail: { cents } })
    )
  }

  // Le même calcul que la remise côté serveur : une journée dont les trois
  // services sont cochés vaut le prix de formule, pas la somme des trois.
  totalCents(checked, people) {
    const kind = this.kindInputs.find((input) => input.checked)?.value
    const forced = this.unitInput?.value ? Math.round(parseFloat(this.unitInput.value.replace(",", ".")) * 100) : null

    // Le jour se lit sur la case (`data-day`), plus dans son `name` : depuis
    // l'issue #265 celui-ci est préfixé par le bloc (`prestations[2][grid][…]`)
    // et l'expression régulière qui cherchait `grid[` n'y trouvait plus rien —
    // le total tombait à zéro sans un mot.
    const byDay = {}
    checked.forEach((cell) => {
      const day = cell.dataset.day
      byDay[day] = byDay[day] || []
      byDay[day].push(cell.dataset.moment)
    })

    return Object.values(byDay).reduce((sum, moments) => {
      const complete = kind === "repas" && forced === null &&
        ["midi", "gouter", "soir"].every((m) => moments.includes(m))

      if (complete) return sum + this.trioValue * people

      return sum + moments.reduce((dayTotal, moment) => {
        const rateKind = moment === "gouter" && kind === "repas" ? "gouter" : kind
        const unit = forced !== null ? forced : (this.ratesValue[rateKind] || 0)
        return dayTotal + unit * people
      }, 0)
    }, 0)
  }
}
