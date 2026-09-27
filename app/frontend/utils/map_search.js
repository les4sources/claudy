// La recherche de la carte (epic #348, phase 14).
//
// Un champ en tête du panneau, PROPRE au mode actif (décision 10 : pas de
// recherche globale) : la couche active dit où l'on cherche, le placeholder dit
// quoi. La recherche se fait côté serveur (`GET /map/search?mode=…&q=…`, JSON
// d'identifiants) : ce qu'on cherche ne vit pas toujours dans le GeoJSON chargé
// (libellés des tâches, messages d'un fil, espèce d'une plante, client du jour).
//
// Effet : les objets trouvés s'ALLUMENT (opacité pleine, halo `ember`, libellé
// forcé même sous le zoom 18) et le reste de la couche s'ESTOMPE à 25 %. Des
// classes CSS plutôt que `setStyle`, comme la vue « ce mois-ci » : la sélection
// réécrit le style d'un tracé, pas ses classes. Le contrôleur rappelle `apply()`
// chaque fois qu'il recrée des éléments (rechargement de couche, `setIcon`).
//
// Entrée : centre sur le premier résultat et ouvre sa fiche ; ‹ › (ou ↑ ↓)
// passent au précédent / suivant ; Échap efface ; changer de couche efface.
//
// Ce module tient l'état de la recherche ; le contrôleur `map` lui prête sa
// carte, ses couches (`featureLayers`, `findFeatureLayer`), sa sélection
// (`selectFeature`, `selectVenue`, `isVenue`) et sa date (`dateValue`).

const DEBOUNCE_MS = 250;

// Ce que chaque mode cherche — les mêmes champs que `Maps::Search`.
export const SEARCH_PLACEHOLDERS = {
  management: 'Chercher dans la Gestion : nom, consigne, tâche…',
  plants: 'Chercher une plante : nom, espèce, n°…',
  network: 'Chercher un nœud : nom, type, consigne…',
  comments: 'Chercher dans les commentaires…',
  biodiversity: 'Chercher une espèce observée…',
  venues: 'Chercher un gîte, une salle, un client du jour…',
  welcome: "Chercher dans l'Accueil : nom, description…",
};

export function resultsLabel(count) {
  if (count === 0) return 'Aucun résultat';
  return count === 1 ? '1 résultat' : `${count} résultats`;
}

export class MapSearch {
  constructor(controller) {
    this.c = controller;
    this.root = controller.element.querySelector('[data-map-search]');
    this.kind = null;
    this.layerId = null;
    this.hits = null; // Set des ids allumés, ou null sans recherche.
    this.results = [];
    this.index = -1;
    this.timer = null;
    this.sequence = 0;
    if (!this.root) return;

    this.url = this.root.dataset.url;
    this.input = this.root.querySelector('[data-map-search-input]');
    this.counter = this.root.querySelector('[data-map-search-count]');
    this.nav = this.root.querySelector('[data-map-search-nav]');
    this.clearButton = this.root.querySelector('[data-map-search-clear]');
    this.filtersBox = this.root.querySelector('[data-map-search-filters]');
    this.filterFields = Array.from(this.root.querySelectorAll('[data-map-search-filter]'));

    this.onInput = () => this.schedule();
    this.onKeydown = (event) => this.keydown(event);
    this.onFilterChange = () => this.run();
    this.onClick = (event) => {
      const step = event.target.closest('[data-map-search-step]');
      if (step) this.step(Number(step.dataset.mapSearchStep));
      if (event.target.closest('[data-map-search-clear]')) this.clear();
    };
    this.input?.addEventListener('input', this.onInput);
    this.input?.addEventListener('keydown', this.onKeydown);
    this.filterFields.forEach((field) => field.addEventListener('change', this.onFilterChange));
    this.root.addEventListener('click', this.onClick);
    this.update();
  }

  destroy() {
    clearTimeout(this.timer);
    if (!this.root) return;
    this.input?.removeEventListener('input', this.onInput);
    this.input?.removeEventListener('keydown', this.onKeydown);
    this.filterFields.forEach((field) => field.removeEventListener('change', this.onFilterChange));
    this.root.removeEventListener('click', this.onClick);
  }

  get active() {
    return this.hits !== null;
  }

  // La couche active change : la recherche repart de zéro, dans le nouveau mode.
  onActivate(layerId, kind) {
    const changed = String(layerId) !== String(this.layerId) || kind !== this.kind;
    this.layerId = layerId == null ? null : String(layerId);
    this.kind = kind;
    if (changed) this.clear({ keepFocus: false });
    this.update();
  }

  // Le jour affiché change : le client présent n'est plus le même.
  onDateChange() {
    if (this.active && this.kind === 'venues') this.run();
  }

  supported() {
    return Boolean(this.kind && SEARCH_PLACEHOLDERS[this.kind]);
  }

  filters() {
    if (this.kind !== 'plants') return {};
    return Object.fromEntries(
      this.filterFields.filter((field) => field.value).map((field) => [field.dataset.mapSearchFilter, field.value])
    );
  }

  hasCriteria() {
    return Boolean(this.input?.value.trim()) || Object.keys(this.filters()).length > 0;
  }

  schedule() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.run(), DEBOUNCE_MS);
    this.update();
  }

  async run() {
    clearTimeout(this.timer);
    this.timer = null;
    if (!this.url || !this.supported() || !this.hasCriteria()) {
      this.reset();
      return;
    }
    const params = new URLSearchParams({ mode: this.kind, q: this.input.value.trim() });
    if (this.kind === 'network' && this.layerId) params.set('layer_id', this.layerId);
    if (this.kind === 'venues' && this.c.dateValue) params.set('date', this.c.dateValue);
    Object.entries(this.filters()).forEach(([key, value]) => params.set(key, value));

    // Une réponse lente ne doit pas écraser une saisie plus récente.
    const sequence = ++this.sequence;
    let data;
    try {
      const response = await fetch(`${this.url}?${params}`, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      if (!response.ok) throw new Error(String(response.status));
      data = await response.json();
    } catch {
      if (sequence === this.sequence) this.c.showNotice('La recherche ne répond pas — réessayez.');
      return;
    }
    if (sequence !== this.sequence || !this.c.map || data.mode !== this.kind) return;

    this.results = (data.feature_ids || []).map(String);
    this.hits = new Set(this.results);
    this.index = -1;
    this.apply();
    this.update();
  }

  keydown(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      this.clear();
    } else if (event.key === 'Enter') {
      event.preventDefault();
      // La saisie n'est peut-être pas encore partie : on n'attend pas le délai.
      if (this.timer) this.run().then(() => this.goTo(0));
      else this.goTo(0);
    } else if (event.key === 'ArrowDown' && this.results.length) {
      event.preventDefault();
      this.step(1);
    } else if (event.key === 'ArrowUp' && this.results.length) {
      event.preventDefault();
      this.step(-1);
    }
  }

  step(delta) {
    if (!this.results.length) return;
    const count = this.results.length;
    this.goTo(this.index < 0 ? (delta > 0 ? 0 : count - 1) : (this.index + delta + count) % count);
  }

  // Centre la carte sur le n-ième résultat et ouvre sa fiche — la même
  // mécanique que `/map?feature=<id>` (focusFeature).
  goTo(index) {
    const id = this.results[index];
    const found = id && this.c.findFeatureLayer(id);
    if (!found) return;
    this.index = index;
    const { layer } = found;
    const wide = window.matchMedia('(min-width: 768px)').matches;
    const padding = {
      paddingTopLeft: wide ? [300, 90] : [40, 40],
      paddingBottomRight: wide ? [420, 110] : [40, 40],
      maxZoom: 19,
    };
    if (layer.getBounds) this.c.map.fitBounds(layer.getBounds(), padding);
    else if (layer.getLatLng) this.c.map.setView(layer.getLatLng(), Math.max(this.c.map.getZoom(), 19));
    if (this.c.isVenue(layer.feature)) this.c.selectVenue(layer.featureId);
    else this.c.selectFeature(layer.featureId);
    this.update();
  }

  // Efface la saisie, les filtres et l'effet sur la carte.
  clear({ keepFocus = true } = {}) {
    clearTimeout(this.timer);
    this.timer = null;
    this.sequence++;
    if (this.input) this.input.value = '';
    this.filterFields.forEach((field) => {
      field.value = '';
    });
    this.reset();
    if (keepFocus && this.input && document.activeElement === this.input) this.input.focus();
  }

  reset() {
    this.timer = null;
    this.hits = null;
    this.results = [];
    this.index = -1;
    this.apply();
    this.update();
  }

  // Pose (ou retire) les classes sur les éléments de la couche active. Les
  // autres couches ne sont pas touchées : la recherche est celle du mode.
  apply() {
    Object.entries(this.c.featureLayers || {}).forEach(([layerId, group]) => {
      const searched = this.active && String(layerId) === this.layerId;
      group.eachLayer((layer) => {
        const hit = searched && this.hits.has(String(layer.featureId));
        const dimmed = searched && !hit;
        const element = layer.getElement?.();
        if (element) {
          element.classList.toggle('map-search-hit', hit);
          element.classList.toggle('map-search-dimmed', dimmed);
        }
        const tooltip = layer.getTooltip?.()?.getElement?.();
        if (tooltip) {
          tooltip.classList.toggle('map-search-label', hit);
          tooltip.classList.toggle('map-search-dimmed', dimmed);
        }
        // Un résultat passe devant ses voisins estompés.
        if (hit && layer.bringToFront) layer.bringToFront();
      });
    });
  }

  update() {
    if (!this.root) return;
    const supported = this.supported();
    if (this.input) {
      this.input.disabled = !supported;
      this.input.placeholder = supported
        ? SEARCH_PLACEHOLDERS[this.kind]
        : this.kind
          ? 'Pas de recherche dans cette couche'
          : 'Choisissez une couche pour chercher';
    }
    if (this.filtersBox) this.filtersBox.classList.toggle('hidden', this.kind !== 'plants');
    const pending = Boolean(this.timer);
    if (this.counter) {
      this.counter.classList.toggle('hidden', !this.active && !pending);
      this.counter.textContent = pending
        ? 'Recherche…'
        : this.index >= 0
          ? `${this.index + 1} / ${this.results.length}`
          : resultsLabel(this.results.length);
    }
    if (this.nav) {
      const navigable = this.active && this.results.length > 0;
      this.nav.classList.toggle('hidden', !navigable);
      this.nav.classList.toggle('flex', navigable);
    }
    if (this.clearButton) this.clearButton.classList.toggle('hidden', !this.active && !this.hasCriteria());
  }
}
