import { Controller } from "@hotwired/stimulus"

// Lit les champs date d'arrivée / départ de l'étape 1 du funnel /reservation et
// affiche dynamiquement le nombre de nuits entre les deux. Pose aussi le `min`
// du départ à arrivée + 1 jour pour empêcher un départ antérieur à l'arrivée,
// et vide le départ s'il devient invalide après mise à jour du `min`.
const MS_PER_DAY = 1000 * 60 * 60 * 24

export default class extends Controller {
  static targets = ["arrival", "departure", "nights"]

  // Action — câblée sur `change` des deux inputs date.
  compute() {
    this.enforceDepartureMin()
    this.renderNights()
  }

  // Calcule le nombre de nuits ; rend "= N nuit"/"= N nuits", ou vide la cible
  // si l'une des dates manque/est invalide ou si l'écart est ≤ 0.
  renderNights() {
    if (!this.hasNightsTarget) return

    const nights = this.nightsBetween()
    if (nights === null || nights <= 0) {
      this.nightsTarget.textContent = ""
      return
    }

    const noun = nights === 1 ? "nuit" : "nuits"
    this.nightsTarget.textContent = `= ${nights} ${noun}`
  }

  // Nombre de nuits entières entre arrivée et départ, ou null si indéterminable.
  nightsBetween() {
    const arrival = this.parseDate(this.hasArrivalTarget ? this.arrivalTarget.value : "")
    const departure = this.parseDate(this.hasDepartureTarget ? this.departureTarget.value : "")
    if (arrival === null || departure === null) return null

    return Math.round((departure - arrival) / MS_PER_DAY)
  }

  // Borne le départ à arrivée + 1 jour. Si le départ déjà saisi tombe avant ce
  // nouveau `min`, on le vide pour forcer une nouvelle sélection cohérente.
  enforceDepartureMin() {
    if (!this.hasArrivalTarget || !this.hasDepartureTarget) return

    const arrival = this.parseDate(this.arrivalTarget.value)
    if (arrival === null) {
      // Pas d'arrivée valide : on retire toute contrainte héritée d'avant.
      this.departureTarget.removeAttribute("min")
      return
    }

    const minDeparture = new Date(arrival.getTime() + MS_PER_DAY)
    const minIso = this.toIso(minDeparture)
    this.departureTarget.min = minIso

    const departure = this.parseDate(this.departureTarget.value)
    if (departure !== null && departure < minDeparture) {
      this.departureTarget.value = ""
    }
  }

  // Parse une valeur "YYYY-MM-DD" en Date UTC (midi UTC pour neutraliser tout
  // décalage de fuseau), ou null si vide/malformée. On valide la forme avant de
  // faire confiance à la chaîne issue de l'input.
  parseDate(value) {
    if (typeof value !== "string") return null
    const trimmed = value.trim()
    if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return null

    const [year, month, day] = trimmed.split("-").map(Number)
    const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0))
    if (Number.isNaN(date.getTime())) return null

    // Rejette les dates « débordées » (ex. 2026-02-31 → 2026-03-03).
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
      return null
    }
    return date
  }

  // Sérialise une Date en "YYYY-MM-DD" pour l'attribut `min` de l'input date.
  toIso(date) {
    const year = String(date.getUTCFullYear()).padStart(4, "0")
    const month = String(date.getUTCMonth() + 1).padStart(2, "0")
    const day = String(date.getUTCDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }
}
