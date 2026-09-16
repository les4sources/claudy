import { Controller } from "@hotwired/stimulus"

// Copier une valeur en un clic (epic #240, phase 4).
//
// La file « À payer » se lit devant l'interface de la banque : on recopie un
// IBAN et une communication à la main, à l'œil, dans un autre onglet. Une
// faute de frappe sur un IBAN, c'est un virement qui part ailleurs. Le bouton
// copie et le DIT — un retour muet laisse douter et on recopie quand même.
//
// Usage (Slim) :
//   button data-controller="copy" data-copy-value-value="BE68..." \
//          data-action="copy#copy" Copier
export default class extends Controller {
  static values = { value: String, label: { type: String, default: "Copié !" } }

  copy(event) {
    event.preventDefault()

    const done = () => this.#flash()
    // `navigator.clipboard` n'existe pas hors contexte sécurisé (http sur une
    // IP du réseau local, cas courant ici) : on retombe alors sur un champ
    // temporaire, qui marche partout.
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(this.valueValue).then(done, () => this.#fallback(done))
    } else {
      this.#fallback(done)
    }
  }

  #fallback(done) {
    const field = document.createElement("textarea")
    field.value = this.valueValue
    field.setAttribute("readonly", "")
    field.style.position = "absolute"
    field.style.left = "-9999px"
    document.body.appendChild(field)
    field.select()
    try {
      document.execCommand("copy")
      done()
    } finally {
      document.body.removeChild(field)
    }
  }

  #flash() {
    if (this.restoring) return

    const original = this.element.textContent
    this.element.textContent = this.labelValue
    this.restoring = setTimeout(() => {
      this.element.textContent = original
      this.restoring = null
    }, 1500)
  }
}
