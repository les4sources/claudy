import { Controller } from '@hotwired/stimulus';

// L'éditeur du calendrier de récolte d'une plante (epic #348, phase 7). Le
// serveur rend les sept parties ; celles sans fenêtre sont des `fieldset`
// cachés ET désactivés, donc absents de l'envoi. Ajouter une partie la révèle
// (et l'active), la retirer la cache (et la désactive) : rien n'est enregistré
// avant « Enregistrer le calendrier », qui remplace l'ensemble des fenêtres.
export default class extends Controller {
  static targets = ['row', 'picker', 'adder', 'empty'];

  connect() {
    this.sync();
  }

  add() {
    const row = this.row(this.pickerTarget.value);
    if (!row) return;

    this.toggle(row, true);
    this.sync();
    row.querySelector('input[type="checkbox"]')?.focus();
  }

  remove(event) {
    const row = this.row(event.currentTarget.dataset.part);
    if (!row) return;

    this.toggle(row, false);
    this.sync();
  }

  // --- privé -------------------------------------------------------------

  row(part) {
    return this.rowTargets.find((row) => row.dataset.part === part);
  }

  toggle(row, visible) {
    row.hidden = !visible;
    row.disabled = !visible;
  }

  // Le sélecteur ne propose que les parties absentes ; il disparaît quand les
  // sept sont là, et le message « aucune partie » quand il y en a une.
  sync() {
    const absent = new Set(this.rowTargets.filter((row) => row.hidden).map((row) => row.dataset.part));
    Array.from(this.pickerTarget.options).forEach((option) => {
      if (option.value) option.disabled = option.hidden = !absent.has(option.value);
    });
    this.pickerTarget.value = '';
    this.adderTarget.hidden = absent.size === 0;
    if (this.hasEmptyTarget) this.emptyTarget.hidden = absent.size !== this.rowTargets.length;
  }
}
