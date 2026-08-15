import { Controller } from "@hotwired/stimulus"

// Rend un tableau lisible sur téléphone en posant sur chaque cellule l'intitulé
// de sa colonne (`data-label`). La feuille de style s'en sert pour transformer,
// sous `md`, chaque ligne en carte.
//
// Pourquoi un contrôleur plutôt que des `data-label` écrits dans les vues : il y
// a douze tableaux dans la section Finances, et une colonne renommée dans un
// `thead` doit rester juste sur mobile sans que personne n'ait à y penser. Le
// `thead` est déjà la source de vérité — autant la lire.
export default class extends Controller {
  connect() {
    this.label()
    // Turbo remplace des fragments de tableau (émission d'un décompte,
    // affectation d'une ligne) sans reconnecter le contrôleur : on réétiquette
    // à chaque mutation du corps du tableau.
    this.observer = new MutationObserver(() => this.label())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  label() {
    const headers = Array.from(this.element.querySelectorAll("thead th")).map((th) =>
      th.textContent.trim()
    )
    if (headers.length === 0) return

    this.element.querySelectorAll("tbody tr").forEach((row) => {
      // On avance d'autant de colonnes que la cellule en occupe : une ligne de
      // total avec un `colspan` décalait sinon tous les intitulés suivants, et
      // la carte annonçait « Compte » au-dessus d'un montant.
      let column = 0
      Array.from(row.children).forEach((cell) => {
        const span = parseInt(cell.getAttribute("colspan") || "1", 10)
        const label = span > 1 ? "" : (headers[column] ?? "")
        if (cell.getAttribute("data-label") !== label) {
          cell.setAttribute("data-label", label)
        }
        column += span
      })
    })

    if (!this.element.hasAttribute("data-stacked-table")) {
      this.element.setAttribute("data-stacked-table", "")
    }
  }
}
