import { Controller } from '@hotwired/stimulus';

// Le formulaire multi-lignes d'une note de frais (epic #241, phase 1).
//
// Il est écrit pour UN geste précis : la compta a une feuille papier de six
// dépenses devant elle et la recopie d'une traite. Trois choses lui font gagner
// la passe :
//
//   1. « Ajouter une ligne » n'attend pas le serveur (même patron que
//      `nested_form` : un <template> avec l'index NEW_RECORD réindexé à chaque
//      insertion) ;
//   2. la ligne ajoutée HÉRITE du pôle, du compte et de la date de la
//      précédente — sur une feuille, six dépenses tombent presque toujours dans
//      le même pôle et le même compte ;
//   3. le total se met à jour en direct, ce qui permet de le comparer au total
//      écrit en bas de la feuille AVANT d'enregistrer.
//
// Retirer une ligne : une ligne jamais enregistrée disparaît du DOM ; une ligne
// existante coche son `_destroy` caché et s'efface visuellement — Rails ne la
// supprime qu'à l'enregistrement, et l'annulation reste possible.
export default class extends Controller {
  static targets = ['rows', 'template', 'row', 'amount', 'total', 'count'];
  static values = { placeholder: { type: String, default: 'NEW_RECORD' } };

  connect() {
    this.counter = 0;
    this.refresh();
  }

  add(event) {
    event.preventDefault();

    const html = this.templateTarget.innerHTML.replaceAll(
      this.placeholderValue,
      this.nextIndex()
    );
    this.rowsTarget.insertAdjacentHTML('beforeend', html);

    const row = this.rowsTarget.lastElementChild;
    this.inherit(row);
    this.refresh();

    // Le curseur atterrit sur le libellé : la date et le compte viennent
    // d'être hérités, ce qui reste à taper c'est ce que la dépense était.
    row?.querySelector('[data-expense-field="label"]')?.focus();
  }

  remove(event) {
    event.preventDefault();

    const row = event.target.closest('[data-expense-lines-target="row"]');
    if (!row) return;

    const destroyField = row.querySelector('input[name*="_destroy"]');
    if (destroyField) {
      destroyField.value = '1';
      row.classList.add('hidden');
      row.dataset.removed = 'true';
    } else {
      row.remove();
    }

    this.refresh();
  }

  // Appelée à chaque saisie de montant (`data-action="input->expense-lines#refresh"`).
  refresh() {
    const cents = this.amountTargets
      .filter((field) => !field.closest('[data-removed="true"]'))
      .reduce((sum, field) => sum + this.parseCents(field.value), 0);

    if (this.hasTotalTarget) this.totalTarget.textContent = this.formatEuros(cents);
    if (this.hasCountTarget) {
      const lines = this.rowTargets.filter((row) => row.dataset.removed !== 'true').length;
      this.countTarget.textContent = lines === 1 ? '1 ligne' : `${lines} lignes`;
    }
  }

  // Le pôle, le compte et la date de la dernière ligne visible. Recopiés, pas
  // imposés : tout reste modifiable ligne par ligne.
  inherit(row) {
    const previous = this.rowTargets.filter(
      (candidate) => candidate !== row && candidate.dataset.removed !== 'true'
    ).pop();
    if (!previous || !row) return;

    ['general_account_id', 'team_id', 'spent_on'].forEach((field) => {
      const source = previous.querySelector(`[data-expense-field="${field}"]`);
      const target = row.querySelector(`[data-expense-field="${field}"]`);
      if (source && target && source.value) target.value = source.value;
    });
  }

  parseCents(raw) {
    const normalized = String(raw || '').replace(/\s/g, '').replace(',', '.');
    const value = Number.parseFloat(normalized);
    return Number.isFinite(value) ? Math.round(value * 100) : 0;
  }

  formatEuros(cents) {
    return new Intl.NumberFormat('fr-BE', {
      style: 'currency',
      currency: 'EUR'
    }).format(cents / 100);
  }

  nextIndex() {
    this.counter += 1;
    return `${Date.now()}${this.counter}`;
  }
}
