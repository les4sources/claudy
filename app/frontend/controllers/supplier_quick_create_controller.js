import { Controller } from "@hotwired/stimulus"

// Créer un fournisseur sans quitter la facture qu'on encode (messagerie, 2026-09-30).
//
// La liste des tiers de prod était vide : chaque facture reçue par mail tombait
// sur un fournisseur « inconnu », et aller le créer dans Tiers faisait perdre la
// facture à moitié remplie. La fenêtre s'ouvre ici, pré-remplie avec ce que
// Claudy a lu dans le PDF (nom, TVA, IBAN) ; à l'enregistrement, le nouveau
// fournisseur prend sa place dans la liste — par ordre alphabétique — et s'y
// sélectionne.
//
// Les champs de la fenêtre n'ont PAS d'attribut `name` : ils vivent à
// l'intérieur du formulaire de la facture (on ne peut pas imbriquer deux
// <form>), et ne doivent pas partir avec elle.
export default class extends Controller {
  static targets = ["dialog", "select", "name", "vat", "iban", "email", "error", "submit"]
  static values = { url: String }

  open(event) {
    event.preventDefault()
    this.errorTarget.textContent = ""
    this.dialogTarget.showModal()
    this.nameTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.close()
  }

  // Entrée dans un champ de la fenêtre soumettrait la FACTURE : on l'intercepte.
  submitOnEnter(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    this.create(event)
  }

  async create(event) {
    event.preventDefault()
    this.submitTarget.disabled = true
    this.errorTarget.textContent = ""

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({
          third_party: {
            name: this.nameTarget.value,
            vat_number: this.vatTarget.value,
            iban: this.ibanTarget.value,
            email: this.emailTarget.value
          }
        })
      })
      const data = await response.json()

      if (!response.ok) {
        this.errorTarget.textContent = (data.errors || ["Le fournisseur n'a pas pu être créé."]).join(" · ")
        return
      }

      this.select(data)
      this.dialogTarget.close()
    } catch (_error) {
      this.errorTarget.textContent = "Claudy ne répond pas — réessaie dans un instant."
    } finally {
      this.submitTarget.disabled = false
    }
  }

  // Inséré à sa place alphabétique, comme le serveur l'aurait rangé.
  select({ id, name }) {
    const option = new Option(name, id)
    const suivante = Array.from(this.selectTarget.options)
      .find((o) => o.value !== "" && o.text.localeCompare(name, "fr", { sensitivity: "base" }) > 0)
    this.selectTarget.add(option, suivante || null)
    this.selectTarget.value = String(id)
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
