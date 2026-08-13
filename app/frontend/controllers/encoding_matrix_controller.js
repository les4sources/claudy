import { Controller } from '@hotwired/stimulus';

// L'écran d'encodage matriciel (issue #158) — celui qui décide de l'adoption.
// Si encoder une fiche de bar prend plus longtemps qu'avant, la comptabilité
// rouvrira son tableur.
//
// Trois comportements, tous au service du geste réel :
//
// LE CLAVIER SUIT LA COLONNE. On encode une fiche à la fois, c'est-à-dire un
// compte à la fois, du haut vers le bas. Tab et Entrée descendent donc dans la
// colonne courante, pas dans la ligne — l'inverse du comportement natif d'un
// tableau HTML, qui obligerait à traverser tous les autres comptes entre deux
// produits du même sourcier.
//
// LES TOTAUX SE RECALCULENT EN DIRECT. Sans aller-retour serveur : le total de
// colonne est ce qu'on compare à la fiche papier avant d'enregistrer.
//
// LA BASCULE MONTANT / QUANTITÉ. Le tableur actuel contient des montants, la
// nouvelle vie contiendra des quantités. Les deux modes coexistent, et le total
// se calcule différemment selon le mode.
export default class extends Controller {
  static targets = ['cell', 'columnTotal', 'grandTotal', 'modeInput', 'modeLabel'];
  static values = { mode: String };

  connect() {
    this.recomputeAll();
  }

  // Bascule globale montant <-> quantité. On ne convertit PAS les valeurs
  // saisies : elles n'ont pas le même sens d'un mode à l'autre, et convertir
  // silencieusement produirait des chiffres que personne n'a écrits.
  toggleMode() {
    this.modeValue = this.modeValue === 'quantity' ? 'amount' : 'quantity';
    this.modeInputTarget.value = this.modeValue;
    this.modeLabelTarget.textContent =
      this.modeValue === 'quantity' ? 'Je saisis des quantités' : 'Je saisis des montants';
    this.recomputeAll();
  }

  // La matrice desktop et l'accordéon mobile rendent DEUX champs par cellule,
  // avec le même `name`. On les tient synchronisés à la frappe, sinon basculer
  // de mise en page ferait apparaître une grille vide.
  recompute(event) {
    const cell = event?.target;
    if (cell?.name) {
      this.cellTargets
        .filter((other) => other !== cell && other.name === cell.name)
        .forEach((twin) => {
          twin.value = cell.value;
        });
    }

    this.recomputeAll();
  }

  // …et surtout, on ne soumet QUE la mise en page active. Deux champs de même
  // nom, c'est le dernier qui gagne côté Rails : sans ce filtre, une saisie
  // faite sur la matrice desktop serait écrasée par le champ mobile caché, et
  // la fiche partirait vide sans un seul message d'erreur. Constaté au
  // navigateur — aucune spec request ne pouvait le voir, elles postent les
  // paramètres directement.
  submit(event) {
    const desktop = window.matchMedia('(min-width: 768px)').matches;
    const inactive = desktop ? 'mobile' : 'desktop';

    this.cellTargets
      .filter((cell) => cell.dataset.layout === inactive)
      .forEach((cell) => {
        cell.disabled = true;
      });

    if (event?.target && !event.target.checkValidity?.()) return;
  }

  recomputeAll() {
    const totals = new Map();

    // On n'agrège QU'UNE seule mise en page. Chaque cellule existe en double —
    // matrice desktop et accordéon mobile, tenus synchronisés par `recompute` —
    // et les compter toutes doublerait chaque total.
    this.cellTargets.forEach((cell) => {
      if (cell.dataset.layout === 'mobile') return;

      const value = this.parse(cell.value);
      if (value === null) return;

      const cents =
        this.modeValue === 'quantity'
          ? Math.round(value * Number(cell.dataset.unitPriceCents || 0))
          : Math.round(value * 100);

      const account = cell.dataset.accountId;
      totals.set(account, (totals.get(account) || 0) + cents);
    });

    // Le total général se calcule depuis la Map, PAS en sommant les nœuds
    // d'affichage : chaque compte a deux totaux dans le DOM — un pour la
    // matrice desktop, un pour l'accordéon mobile — et les additionner
    // doublerait le total (constaté au navigateur : 24,48 € au lieu de 12,24 €).
    let grand = 0;
    totals.forEach((cents) => {
      grand += cents;
    });

    this.columnTotalTargets.forEach((node) => {
      node.textContent = this.format(totals.get(node.dataset.accountId) || 0);
    });

    if (this.hasGrandTotalTarget) this.grandTotalTarget.textContent = this.format(grand);
  }

  // Tab / Entrée descendent la colonne ; Maj+Tab remonte.
  navigate(event) {
    if (event.key !== 'Tab' && event.key !== 'Enter') return;

    const cell = event.target;
    const column = this.cellTargets.filter((c) => c.dataset.accountId === cell.dataset.accountId);
    const index = column.indexOf(cell);
    if (index === -1) return;

    const next = event.shiftKey ? column[index - 1] : column[index + 1];
    if (!next) return; // bord de colonne : on laisse le comportement natif

    event.preventDefault();
    next.focus();
    next.select();
  }

  parse(raw) {
    const value = String(raw).trim().replace(',', '.');
    if (value === '' || !/^-?\d+(\.\d+)?$/.test(value)) return null;
    return Number(value);
  }

  format(cents) {
    return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
  }
}
