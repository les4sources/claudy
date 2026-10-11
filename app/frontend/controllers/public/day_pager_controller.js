import { Controller } from "@hotwired/stimulus"

// Grilles « nuit par nuit » et « jour par jour » sur téléphone (Michael,
// 2026-10-11 : « il ne faudrait pas que l'utilisateur doive scroller
// horizontalement »).
//
// Sur un écran large, la grille montre toutes ses colonnes. Sous 640 px, elle
// n'en montre plus qu'UNE, et une rangée de pastilles au-dessus (une par nuit
// ou par jour, qui passent à la ligne au lieu de déborder) choisit laquelle.
// Plus de défilement horizontal, plus d'en-tête de section coupé à moitié.
//
// Les colonnes sont repérées par `data-day-index` (en-têtes ET cellules) ; le
// libellé de chaque pastille vient de `data-day-short` sur l'en-tête. Une
// colonne masquée garde ses champs : le formulaire poste toujours toutes les
// nuits, rien ne change côté serveur.
const MOBILE = "(max-width: 639px)"

export default class extends Controller {
  // `noun` : « Nuit » (hébergement) ou « Jour » (salles), pour les libellés
  // lus par un lecteur d'écran.
  static values = { noun: { type: String, default: "Nuit" } }

  connect() {
    this.index = 0
    this.media = window.matchMedia(MOBILE)
    this.onMediaChange = () => this.render()
    this.media.addEventListener("change", this.onMediaChange)
    // Chaque case de la grille émet un `change` qui remonte (sélection d'un
    // gîte, stepper, créneau de salle) : les pastilles suivent. Écouté sur le
    // document, parce que la grille des gîtes l'émet depuis sa racine, AU-DESSUS
    // de cet élément.
    this.onGridChange = () => this.markFilled()
    document.addEventListener("change", this.onGridChange)
    this.render()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onMediaChange)
    document.removeEventListener("change", this.onGridChange)
    this.removeNav()
    this.showAll()
    this.element.classList.remove("day-pager--on")
  }

  get headers() {
    return Array.from(this.element.querySelectorAll("th[data-day-index]"))
  }

  render() {
    const count = this.headers.length
    const active = this.media.matches && count > 1

    this.element.classList.toggle("day-pager--on", active)
    if (!active) {
      this.removeNav()
      this.showAll()
      return
    }

    this.index = Math.min(this.index, count - 1)
    this.buildNav()
    this.show(this.index)
    this.markFilled()
  }

  // Une pastille marquée = une colonne où le client a déjà choisi quelque
  // chose. Sans elle, une nuit oubliée ne se voyait qu'en passant les nuits
  // une à une.
  markFilled() {
    if (!this.nav) return

    this.nav.querySelectorAll("[data-day-pager-chip]").forEach((chip) => {
      const cells = this.element.querySelectorAll(`td[data-day-index="${chip.dataset.dayPagerChip}"]`)
      const filled = Array.from(cells).some((cell) =>
        cell.querySelector('[aria-pressed="true"]') ||
        Array.from(cell.querySelectorAll('input[type="hidden"]')).some((input) => input.value !== "" && input.value !== "0")
      )
      chip.classList.toggle("day-pager__chip--filled", filled)
    })
  }

  show(index) {
    this.index = index
    this.element.querySelectorAll("[data-day-index]").forEach((cell) => {
      cell.classList.toggle("day-pager__off", Number(cell.dataset.dayIndex) !== index)
    })

    if (!this.nav) return
    this.nav.querySelectorAll("[data-day-pager-chip]").forEach((chip) => {
      chip.setAttribute("aria-pressed", String(Number(chip.dataset.dayPagerChip) === index))
    })
    this.prevButton.disabled = index === 0
    this.nextButton.disabled = index === this.headers.length - 1
  }

  showAll() {
    this.element.querySelectorAll(".day-pager__off").forEach((cell) => cell.classList.remove("day-pager__off"))
  }

  previous() {
    if (this.index > 0) this.show(this.index - 1)
  }

  next() {
    if (this.index < this.headers.length - 1) this.show(this.index + 1)
  }

  buildNav() {
    if (this.nav) return

    const noun = this.nounValue
    const nav = document.createElement("div")
    nav.className = "day-pager"
    nav.setAttribute("role", "group")
    nav.setAttribute("aria-label", `Choisir la ${noun.toLowerCase()} affichée`)

    this.prevButton = this.arrow("‹", `${noun} précédente`, () => this.previous())
    this.nextButton = this.arrow("›", `${noun} suivante`, () => this.next())

    const chips = document.createElement("div")
    chips.className = "day-pager__chips"
    this.headers.forEach((th, i) => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "day-pager__chip"
      chip.dataset.dayPagerChip = String(i)
      chip.textContent = th.dataset.dayShort || `${noun} ${i + 1}`
      chip.setAttribute("aria-label", `${noun} ${i + 1} : ${chip.textContent}`)
      chip.addEventListener("click", () => this.show(i))
      chips.appendChild(chip)
    })

    nav.append(this.prevButton, chips, this.nextButton)
    this.element.before(nav)
    this.nav = nav
  }

  arrow(glyph, label, onClick) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "day-pager__arrow"
    button.textContent = glyph
    button.setAttribute("aria-label", label)
    button.addEventListener("click", onClick)
    return button
  }

  removeNav() {
    if (!this.nav) return
    this.nav.remove()
    this.nav = null
  }
}
