import { Controller } from "@hotwired/stimulus"

// Formulaire d'un article du catalogue (epic #359, phase 1).
//
// Le sélecteur d'artisan n'a de sens que sur le canal « Artisanat » : ailleurs
// il est interdit par le modèle, donc on le cache au lieu de laisser quelqu'un
// le remplir pour rien.
export default class extends Controller {
  static targets = ["channel", "consignorField", "consignor"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasConsignorFieldTarget) return

    const craft = this.hasChannelTarget && this.channelTarget.value === "craft"
    this.consignorFieldTarget.hidden = !craft
    if (!craft && this.hasConsignorTarget) this.consignorTarget.value = ""
  }
}
