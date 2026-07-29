import { Controller } from "@hotwired/stimulus"

// Cellule de la grille « Espaces » du funnel B2C. Gère un seul créneau
// (un espace × une nuit). Clic = cycle — → Journée → Soirée → J+S → —.
// Un input[type=hidden] synchronisé transmet la valeur au formulaire.
//
// L'état est porté par l'attribut `data-slot` du bouton ; tout le dessin vit
// dans `.funnel-slot[data-slot="…"]` (funnel.css). Avant, ce contrôleur
// transportait une table de classes Tailwind que la légende du template
// recopiait à la main — deux endroits à garder d'accord pour une seule vérité,
// et trois teintes (bleu, violet, sarcelle) étrangères à la charte.
const PERIODS = ["", "journee", "soiree", "journee_et_soiree"]
const LABELS = { "": "—", journee: "Jour", soiree: "Soir", journee_et_soiree: "J+S" }

export default class extends Controller {
  static targets = ["button", "input"]

  connect() {
    this.updateDisplay(this.inputTarget.value || "")
  }

  toggle() {
    const current = this.inputTarget.value || ""
    const idx = PERIODS.indexOf(current)
    const next = PERIODS[(idx + 1) % PERIODS.length]
    this.inputTarget.value = next
    this.updateDisplay(next)
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  updateDisplay(period) {
    const btn = this.buttonTarget
    const known = PERIODS.includes(period) ? period : ""
    btn.textContent = LABELS[known]
    btn.dataset.slot = known
    // `aria-pressed` dirait juste « enfoncé / relâché » là où il y a trois états
    // utiles : on laisse le libellé écrit porter le sens, et on complète le nom
    // accessible (posé côté serveur : espace + nuit) par l'état courant.
    const base = btn.getAttribute("data-label-base") || btn.getAttribute("aria-label") || ""
    if (!btn.getAttribute("data-label-base") && base) btn.setAttribute("data-label-base", base)
    const stem = btn.getAttribute("data-label-base")
    if (stem) {
      const suffix = known === "" ? "aucun créneau" : LABELS[known].toLowerCase()
      btn.setAttribute("aria-label", `${stem} — ${suffix}`)
    }
  }
}
