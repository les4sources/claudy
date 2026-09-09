import { Controller } from "@hotwired/stimulus"

// Le champ « Prix par personne » portait le tarif du barème en placeholder :
// calculé au rendu pour le type initial, il ne bougeait plus et annonçait donc
// un prix faux dès qu'on changeait de type. L'information reste utile — au
// téléphone, c'est le chiffre qu'on annonce au client — mais elle appartient à
// l'aide sous le champ, qui elle suit le type coché.
export default class extends Controller {
  static targets = ["hint"]
  static values = { rates: Object }

  connect() {
    this.refresh()
  }

  refresh() {
    // Suffixe du `name` plutôt que son nom complet : le champ s'appelle
    // `meal_order[kind]` à l'édition et `prestations[2][kind]` à la saisie
    // (issue #265), et l'aide doit suivre le type de SON bloc.
    const kind = this.element.querySelector('input[type="radio"][name$="[kind]"]:checked')?.value
    const rate = kind && this.ratesValue[kind]
    this.hintTarget.textContent = rate
      ? `Laisser vide pour appliquer le barème : ${rate} €/pers.`
      : "Laisser vide pour appliquer le tarif du barème."
  }
}
