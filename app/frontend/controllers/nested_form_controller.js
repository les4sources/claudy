import { Controller } from '@hotwired/stimulus';

// Ajoute une ligne à un formulaire imbriqué (`fields_for`) sans aller-retour
// serveur. Premier contrôleur de ce genre dans l'app — écrit générique parce
// que la composition d'un ménage ne sera pas le dernier formulaire à en avoir
// besoin (issue #155 ; les charges récurrentes suivront).
//
// Le gabarit d'une ligne vierge vit dans un `<template>` rendu par le serveur,
// où l'index des champs est le placeholder `NEW_RECORD`. Il est remplacé à
// chaque insertion par un index unique : c'est ce qui évite que deux lignes
// ajoutées de suite écrasent leurs paramètres l'une l'autre, puisque Rails
// regroupe les `*_attributes` par index.
//
// L'index part de l'horodatage courant, donc toujours au-dessus des index
// 0..n-1 rendus par le serveur — aucune collision possible avec une ligne
// existante, même après plusieurs échecs de validation.
export default class extends Controller {
  static targets = ['rows', 'template'];
  static values = { placeholder: { type: String, default: 'NEW_RECORD' } };

  connect() {
    this.counter = 0;
  }

  add(event) {
    event.preventDefault();

    const html = this.templateTarget.innerHTML.replaceAll(
      this.placeholderValue,
      this.nextIndex()
    );
    this.rowsTarget.insertAdjacentHTML('beforeend', html);

    // Le curseur atterrit dans le premier champ de la ligne ajoutée : on vient
    // de cliquer « Ajouter une personne », la suite du geste est d'écrire son nom.
    this.rowsTarget.lastElementChild?.querySelector('input, select')?.focus();
  }

  nextIndex() {
    this.counter += 1;
    return `${Date.now()}${this.counter}`;
  }
}
