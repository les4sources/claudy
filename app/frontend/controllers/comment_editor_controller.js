import { Controller } from "@hotwired/stimulus"

// Édition d'un commentaire en place (epic #242, phase 1).
//
// Chaque ligne du fil embarque son formulaire, masqué. Basculer ne demande donc
// rien au serveur : « Modifier » montre le formulaire, « Annuler » le remasque.
// Seule la soumission part, et la réponse Turbo Stream remplace tout le fil.
export default class extends Controller {
  static targets = ["body", "form"]

  edit() {
    this.bodyTarget.hidden = true
    this.formTarget.hidden = false
    const editor = this.formTarget.querySelector("trix-editor")
    if (editor) editor.focus()
  }

  cancel() {
    this.formTarget.hidden = true
    this.bodyTarget.hidden = false
  }
}
