import { Controller } from '@hotwired/stimulus';

// Les deux onglets du panneau de la carte (Michael, 2026-10-03 : le panneau
// mélangeait tout dans une colonne). « Travailler » choisit la couche active et
// ses actions ; « Afficher » règle ce qu'on voit : fond, relief, Géoportail,
// filtres. Ce contrôleur ne fait que montrer un onglet et compter les cases
// cochées : couches, Géoportail et filtres restent l'affaire du contrôleur
// `map`, qui écoute leurs `change` comme avant.
const TAB_KEY = 'claudy.map.panel.tab';
const ON = ['bg-white', 'font-semibold', 'text-stone-800', 'shadow-sm'];
const OFF = ['text-stone-500', 'hover:text-stone-700'];

export default class extends Controller {
  static targets = ['tab', 'pane', 'seeCount', 'groupCount'];

  connect() {
    this.show(this.readTab() || 'work');
    this.updateCounts();
  }

  select(event) {
    const tab = event.currentTarget.dataset.panelTab;
    this.show(tab);
    this.writeTab(tab);
  }

  // Flèches gauche et droite d'un onglet à l'autre, comme un `tablist` natif.
  keydown(event) {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const index = this.tabTargets.indexOf(event.currentTarget);
    const step = event.key === 'ArrowRight' ? 1 : -1;
    const next = this.tabTargets[(index + step + this.tabTargets.length) % this.tabTargets.length];
    next.focus();
    next.click();
  }

  show(tab) {
    if (!this.tabTargets.some((button) => button.dataset.panelTab === tab)) tab = 'work';
    this.tabTargets.forEach((button) => {
      const on = button.dataset.panelTab === tab;
      button.setAttribute('aria-selected', String(on));
      button.tabIndex = on ? 0 : -1;
      ON.forEach((name) => button.classList.toggle(name, on));
      OFF.forEach((name) => button.classList.toggle(name, !on));
    });
    this.paneTargets.forEach((pane) => {
      pane.classList.toggle('hidden', pane.dataset.panelTab !== tab);
    });
  }

  // Ce qui est allumé dans « Afficher » se lit sans l'ouvrir : le nombre de
  // cases cochées sur l'onglet, et « 1 / 3 » sur chaque groupe du Géoportail
  // replié.
  updateCounts() {
    const pane = this.paneTargets.find((p) => p.dataset.panelTab === 'see');
    if (pane && this.hasSeeCountTarget) {
      const count = pane.querySelectorAll('input[type="checkbox"]:checked').length;
      this.seeCountTarget.textContent = count ? String(count) : '';
      this.seeCountTarget.classList.toggle('hidden', count === 0);
    }
    this.groupCountTargets.forEach((element) => {
      const group = element.closest('details');
      const boxes = group ? group.querySelectorAll('input[type="checkbox"]') : [];
      const checked = [...boxes].filter((box) => box.checked).length;
      element.textContent = `${checked} / ${boxes.length}`;
      element.classList.toggle('text-4s-main', checked > 0);
      element.classList.toggle('font-semibold', checked > 0);
      element.classList.toggle('text-stone-400', checked === 0);
    });
  }

  readTab() {
    try {
      return window.localStorage.getItem(TAB_KEY);
    } catch (_error) {
      return null;
    }
  }

  writeTab(tab) {
    try {
      window.localStorage.setItem(TAB_KEY, tab);
    } catch (_error) {
      // Navigation privée : l'onglet ne se retient pas, rien de plus.
    }
  }
}
