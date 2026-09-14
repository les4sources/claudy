import { Controller } from '@hotwired/stimulus';

// L'aperçu en direct de la saisie du batch cooking (epic #246).
//
// Ce qu'on veut voir AVANT d'enregistrer, en cuisine, sur un téléphone : ce que
// les familles doivent au total, et ce que chaque cuisinier a gagné. Un
// aller-retour serveur pour ça ferait perdre exactement le temps que l'écran
// est censé faire gagner.
//
// LA RÈGLE DU PARTAGE. Ce que se partagent les cuisiniers, c'est le nombre de
// PERSONNES servies — pas le total de portions (issue #307). La rémunération
// ne suit donc pas le multiplicateur « nombre de repas » : la règle sera
// tranchée dans une issue dédiée, et jusque-là elle est gelée sur ce qu'elle
// valait. Changer 5 repas en 10 double la facture des familles et ne touche
// pas d'un centime ce que gagnent les cuisiniers.
//
// Dès que quelqu'un corrige une part à la main, sa ligne devient intouchable :
// on ne réécrit jamais un chiffre que quelqu'un vient de taper. C'est ce que
// porte `data-touched`.
export default class extends Controller {
  static targets = [
    'mealsCount',
    'serving',
    'cookRow',
    'cookToggle',
    'cookPortions',
    'cookDue',
    'billedTotal',
    'dueTotal',
  ];
  static values = { servingPriceCents: Number, cookPriceCents: Number };

  connect() {
    // Une part déjà saisie (session rouverte) est tenue pour voulue : la
    // redistribution ne doit pas écraser ce que le serveur vient de rendre.
    this.cookPortionsTargets.forEach((input) => {
      if (this.parse(input.value) > 0) input.dataset.touched = 'true';
    });
    this.recompute();
  }

  // Une personne servie — ou le nombre de repas — a changé : le total facturé
  // change, et le total à répartir entre cuisiniers avec lui.
  recompute() {
    this.redistribute();
    this.render();
  }

  toggleCook(event) {
    const input = this.portionsInputFor(event.target);
    // Décocher quelqu'un remet sa ligne à zéro ET la rend à nouveau
    // redistribuable : sinon, le recocher lui rendrait une part périmée.
    if (input && !event.target.checked) {
      input.value = '';
      delete input.dataset.touched;
    }
    this.recompute();
  }

  touchCook(event) {
    event.target.dataset.touched = 'true';
    this.render();
  }

  redistribute() {
    const inputs = this.checkedPortionInputs();
    const libres = inputs.filter((input) => input.dataset.touched !== 'true');
    if (libres.length === 0) return;

    const reserve = inputs
      .filter((input) => input.dataset.touched === 'true')
      .reduce((sum, input) => sum + this.parse(input.value), 0);

    // On répartit au MILLIÈME de portion, comme le modèle : cinq portions pour
    // deux cuisiniers font deux parts et demie, pas trois et deux.
    // `peopleServed()`, PAS `totalPortions()` : c'est la ligne qui garantit que
    // le nombre de repas ne change rien à ce que gagnent les cuisiniers.
    const restant = Math.max(Math.round((this.peopleServed() - reserve) * 1000), 0);
    const base = Math.floor(restant / libres.length);
    const reliquat = restant - base * libres.length;

    libres.forEach((input, index) => {
      const milli = base + (index < reliquat ? 1 : 0);
      input.value = milli === 0 ? '' : String(milli / 1000).replace('.', ',');
    });
  }

  render() {
    const portions = this.totalPortions();
    this.billedTotalTarget.textContent = this.format(Math.round(portions * this.servingPriceCentsValue));

    let du = 0;
    this.cookPortionsTargets.forEach((input) => {
      const coche = this.toggleFor(input)?.checked;
      const cents = coche ? Math.round(this.parse(input.value) * this.cookPriceCentsValue) : 0;
      du += cents;

      const affichage = this.dueFor(input);
      if (affichage) affichage.textContent = cents === 0 ? '—' : this.format(cents);
    });

    this.dueTotalTarget.textContent = this.format(du);
  }

  // Les personnes servies, toutes familles confondues.
  peopleServed() {
    return this.servingTargets.reduce((sum, input) => sum + this.parse(input.value), 0);
  }

  // Ce qui est facturé : chaque famille prend tous les repas de la session.
  totalPortions() {
    return this.mealsCount() * this.peopleServed();
  }

  // Une case vidée pendant la frappe ne doit pas faire tomber l'aperçu à zéro
  // le temps que le chiffre suivant arrive : on retombe sur 1 repas, la seule
  // valeur qui ne ment pas sur le nombre de personnes saisies.
  mealsCount() {
    if (!this.hasMealsCountTarget) return 1;

    const meals = this.parse(this.mealsCountTarget.value);
    return meals > 0 ? meals : 1;
  }

  checkedPortionInputs() {
    return this.cookPortionsTargets.filter((input) => this.toggleFor(input)?.checked);
  }

  // Les trois éléments d'une ligne se retrouvent par leur ligne, pas par un
  // index partagé : une ligne masquée ou ajoutée ne décale alors rien.
  rowOf(element) {
    return element.closest('[data-batch-cooking-target~="cookRow"]');
  }

  portionsInputFor(element) {
    return this.rowOf(element)?.querySelector('[data-batch-cooking-target~="cookPortions"]');
  }

  toggleFor(element) {
    return this.rowOf(element)?.querySelector('[data-batch-cooking-target~="cookToggle"]');
  }

  dueFor(element) {
    return this.rowOf(element)?.querySelector('[data-batch-cooking-target~="cookDue"]');
  }

  parse(raw) {
    const value = String(raw ?? '').trim().replace(',', '.');
    if (value === '' || !/^\d+(\.\d+)?$/.test(value)) return 0;
    return Number(value);
  }

  format(cents) {
    return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
  }
}
