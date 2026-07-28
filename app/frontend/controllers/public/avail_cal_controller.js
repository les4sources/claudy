import { Controller } from "@hotwired/stimulus"

// Sélecteur de PLAGE de dates sur le Gantt de disponibilités.
//
// Avant, ce contrôleur ne faisait qu'éclairer une colonne au clic et afficher
// « 📅 mar. 14 sept. 2026 » — une information, rien de plus. Le client devait
// refermer la modale et retaper ses dates à la main dans deux champs
// `jj/mm/aaaa`. Le calendrier montrait les disponibilités sans permettre d'en
// choisir : c'était l'écart le plus visible avec un moteur de réservation
// sérieux, où le calendrier EST le sélecteur.
//
// Désormais : premier clic = arrivée, second clic = départ, la plage s'éclaire,
// et « Choisir ces dates » écrit dans les deux champs de l'étape 1 puis ferme
// la modale. Un re-clic sur l'arrivée annule ; un clic avant l'arrivée
// redémarre la plage à cette date.
const MS_PER_DAY = 1000 * 60 * 60 * 24

export default class extends Controller {
  static targets = ["dayLabel", "summary", "confirm", "hint"]

  connect() {
    this.start = null
    this.end = null
    // Les champs de dates vivent hors de la modale (étape 1). Absents à l'étape
    // 2, où la modale reste une simple consultation : on masque alors le pied.
    this.arrivalInput = document.querySelector('[name="reservation[arrival_date]"]')
    this.departureInput = document.querySelector('[name="reservation[departure_date]"]')
    this.pickable = Boolean(this.arrivalInput && this.departureInput)
    this.seedFromInputs()
    this.render()
  }

  // Reprend la plage déjà saisie dans le formulaire, pour que la modale s'ouvre
  // sur ce que le client a déjà choisi plutôt que sur une ardoise vierge.
  seedFromInputs() {
    if (!this.pickable) return
    const a = this.parse(this.arrivalInput.value)
    const d = this.parse(this.departureInput.value)
    if (a) this.start = a
    if (a && d && d > a) this.end = d
  }

  selectDay(event) {
    const iso = event.currentTarget.dataset.date
    if (!iso) return
    const date = this.parse(iso)
    if (!date) return

    if (!this.pickable) {
      // Mode consultation : on garde l'ancien comportement « une colonne ».
      this.start = this.sameDay(this.start, date) ? null : date
      this.end = null
      this.render()
      return
    }

    if (this.start === null || this.end !== null) {
      // Nouvelle plage.
      this.start = date
      this.end = null
    } else if (this.sameDay(date, this.start)) {
      // Re-clic sur l'arrivée : on annule.
      this.start = null
    } else if (date < this.start) {
      // Clic avant l'arrivée : cette date devient la nouvelle arrivée.
      this.start = date
    } else {
      this.end = date
    }
    this.render()
  }

  // Écrit la plage dans les champs de l'étape 1 et referme la modale.
  // On émet `change` pour que le badge « = N nuits » et le `min` du départ se
  // recalculent exactement comme après une saisie manuelle.
  apply() {
    if (!this.pickable || this.start === null || this.end === null) return

    this.arrivalInput.value = this.iso(this.start)
    this.departureInput.value = this.iso(this.end)
    this.arrivalInput.dispatchEvent(new Event("change", { bubbles: true }))
    this.departureInput.dispatchEvent(new Event("change", { bubbles: true }))

    window.dispatchEvent(new CustomEvent("reservation:dates-picked"))
  }

  render() {
    this.paintCells()
    this.paintFooter()
  }

  paintCells() {
    const cells = this.element.querySelectorAll("[data-date]")
    cells.forEach((cell) => {
      const d = this.parse(cell.dataset.date)
      cell.classList.remove("avail-pick--start", "avail-pick--end", "avail-pick--between")
      if (!d || this.start === null) return

      if (this.sameDay(d, this.start)) {
        cell.classList.add("avail-pick--start")
      } else if (this.end !== null && this.sameDay(d, this.end)) {
        cell.classList.add("avail-pick--end")
      } else if (this.end !== null && d > this.start && d < this.end) {
        cell.classList.add("avail-pick--between")
      }
    })
  }

  paintFooter() {
    if (this.hasDayLabelTarget) {
      // Conservé pour le mode consultation (étape 2).
      if (!this.pickable && this.start) {
        this.dayLabelTarget.textContent = this.formatFr(this.start)
        this.dayLabelTarget.classList.remove("hidden")
      } else {
        this.dayLabelTarget.classList.add("hidden")
        this.dayLabelTarget.textContent = ""
      }
    }

    if (!this.pickable) return

    const nights = this.nights()
    if (this.hasSummaryTarget) {
      if (this.start && this.end) {
        this.summaryTarget.textContent =
          `${this.formatShort(this.start)} → ${this.formatShort(this.end)} · ${nights} nuit${nights > 1 ? "s" : ""}`
      } else if (this.start) {
        this.summaryTarget.textContent = `Arrivée le ${this.formatShort(this.start)}`
      } else {
        this.summaryTarget.textContent = ""
      }
    }

    if (this.hasHintTarget) {
      this.hintTarget.textContent = this.start && !this.end
        ? "Cliquez maintenant votre jour de départ."
        : (this.start ? "" : "Cliquez votre jour d'arrivée dans le calendrier.")
    }

    if (this.hasConfirmTarget) {
      const ready = Boolean(this.start && this.end)
      this.confirmTarget.disabled = !ready
      this.confirmTarget.classList.toggle("opacity-40", !ready)
      this.confirmTarget.classList.toggle("cursor-not-allowed", !ready)
    }
  }

  nights() {
    if (!this.start || !this.end) return 0
    return Math.round((this.end - this.start) / MS_PER_DAY)
  }

  sameDay(a, b) {
    return a instanceof Date && b instanceof Date && a.getTime() === b.getTime()
  }

  parse(value) {
    if (typeof value !== "string") return null
    const t = value.trim()
    if (!/^\d{4}-\d{2}-\d{2}$/.test(t)) return null
    const [y, m, d] = t.split("-").map(Number)
    const date = new Date(Date.UTC(y, m - 1, d, 12, 0, 0))
    if (Number.isNaN(date.getTime())) return null
    if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null
    return date
  }

  iso(date) {
    return [
      String(date.getUTCFullYear()).padStart(4, "0"),
      String(date.getUTCMonth() + 1).padStart(2, "0"),
      String(date.getUTCDate()).padStart(2, "0")
    ].join("-")
  }

  static MONTHS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
  static DAYS = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]

  formatFr(date) {
    const c = this.constructor
    return `${c.DAYS[date.getUTCDay()]} ${date.getUTCDate()} ${c.MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`
  }

  formatShort(date) {
    const c = this.constructor
    return `${date.getUTCDate()} ${c.MONTHS[date.getUTCMonth()]}`
  }
}
