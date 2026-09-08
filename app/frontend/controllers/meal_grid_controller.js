import { Controller } from "@hotwired/stimulus"

// Grille jours × services du formulaire de cuisine (issue #238).
//
// Trois services : les boutons de remplissage, la ligne « Goûter » qui
// n'apparaît que pour la famille « Repas », et le compteur qui annonce en
// direct ce que la demande va coûter — remise de formule comprise, parce que
// c'est le montant que le client verra.
export default class extends Controller {
  static targets = ["cell", "row", "counter"]
  static values = { rates: Object, trio: Number }

  connect() {
    this.kindInputs = Array.from(
      this.element.closest("form").querySelectorAll('input[name="meal_order[kind]"]')
    )
    this.peopleInput = this.element.closest("form").querySelector('input[name="meal_order[people]"]')
    this.unitInput = this.element.closest("form").querySelector('input[name="meal_order[unit_price]"]')

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
      return
    }

    const total = this.totalCents(checked, people)
    const euros = (total / 100).toFixed(2).replace(".", ",")
    const services = `${checked.length} service${checked.length > 1 ? "s" : ""}`
    const convives = `${people} convive${people > 1 ? "s" : ""}`

    this.counterTarget.textContent = `${services} · ${convives} · ${euros} €`
  }

  // Le même calcul que la remise côté serveur : une journée dont les trois
  // services sont cochés vaut le prix de formule, pas la somme des trois.
  totalCents(checked, people) {
    const kind = this.kindInputs.find((input) => input.checked)?.value
    const forced = this.unitInput?.value ? Math.round(parseFloat(this.unitInput.value.replace(",", ".")) * 100) : null

    const byDay = {}
    checked.forEach((cell) => {
      const day = cell.name.match(/grid\[([^\]]+)\]/)[1]
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
