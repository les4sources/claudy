import { Controller } from "@hotwired/stimulus"

// Petite modale de choix (<dialog>) ouverte par un bouton : sert là où un clic
// doit poser une question avant d'agir (ex. confirmer un séjour passé : écrire
// ou non au client). Les choix sont des formulaires ordinaires DANS le dialog ;
// ce contrôleur ne fait qu'ouvrir et fermer.
//
// Usage:
//   div(data-controller="choice-dialog")
//     button(type="button" data-action="choice-dialog#open")
//     dialog(data-choice-dialog-target="dialog")
//       button(type="button" data-action="choice-dialog#close")
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    if (event) event.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }
}
