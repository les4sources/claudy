import { Controller } from '@hotwired/stimulus';

// Feuille de bar d'un séjour (Michael, 2026-10-13) : montant de chaque ligne et
// total recalculés pendant la saisie, et recherche d'un article dans la liste.
// Le serveur reste la source de vérité : ces montants ne sont qu'un aperçu,
// l'enregistrement les recalcule à partir des prix du catalogue.
export default class extends Controller {
  static targets = ['quantity', 'amount', 'total', 'row', 'group', 'search'];

  connect() {
    this.format = new Intl.NumberFormat('fr-BE', { style: 'currency', currency: 'EUR' });
    this.recompute();
  }

  recompute() {
    let total = 0;
    this.quantityTargets.forEach((input, index) => {
      const quantity = Math.max(Math.round(parseFloat(input.value.replace(',', '.')) || 0), 0);
      const cents = quantity * parseInt(input.dataset.unitPriceCents || '0', 10);
      total += cents;
      this.amountTargets[index].textContent = quantity > 0 ? this.format.format(cents / 100) : '';
    });
    this.totalTarget.textContent = this.format.format(total / 100);
  }

  // Masque les articles qui ne correspondent pas, et les catégories vidées.
  filter() {
    const term = this.searchTarget.value.trim().toLowerCase();
    this.rowTargets.forEach((row) => {
      row.hidden = term !== '' && !row.dataset.name.includes(term);
    });
    this.groupTargets.forEach((group) => {
      const visible = Array.from(group.querySelectorAll('[data-bar-sheet-target="row"]')).some((row) => !row.hidden);
      group.hidden = !visible;
    });
  }
}
