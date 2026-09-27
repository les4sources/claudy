// Les notes manuscrites de la carte (epic #348, phase 12).
//
// Des dessins à main levée par-dessus la carte, rangés par dossier dans le
// panneau. La case d'un dessin l'affiche ou le masque (préférence de CE
// navigateur, en `localStorage`) ; son nom le rend ACTIF — un seul à la fois —
// et fait paraître la barre de dessin.
//
// Les tracés sont en coordonnées géographiques `[lat, lng]` : ils restent à leur
// place à tout zoom et sur tout fond. Chaque dessin est un `L.layerGroup` de
// polylines dessinées par UN renderer canvas partagé, dans un volet à part
// (`sketchPane`) qui ne capte aucun événement : les objets des couches, dessous,
// restent cliquables.
//
// Ce module tient l'état des dessins ; le contrôleur `map` lui prête sa carte,
// sa barre Geoman (masquée pendant qu'on dessine) et `showNotice`.

import L from '~/utils/leaflet_global';
import '~/stylesheets/map_sketches.css';

const HIDDEN_KEY = 'claudy.map.sketches.hidden';
const PANE = 'sketchPane';
const INK = '#ffffff';
// Le halo sombre sous le trait blanc : lisible sur l'herbe comme sur le sable.
const HALO = '#1c1917';
const ACTIVE_CLASSES = ['bg-teal-50', 'font-medium', 'text-4s-main'];

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);
}

export class SketchMode {
  constructor(controller) {
    this.c = controller;
    this.root = controller.element.querySelector('[data-map-sketches]');
    this.toolbar = controller.element.querySelector('[data-sketch-toolbar]');
    this.summaries = [];
    // id → { id, strokes, lockVersion, group, layers: Map(strokeId → [halo, trait]) }
    this.loaded = new Map();
    this.activeId = null;
    this.hidden = this.readHidden();
    if (!this.root || !controller.map) return;

    this.list = this.root.querySelector('[data-sketch-list]');
    this.empty = this.root.querySelector('[data-sketch-empty]');
    this.form = this.root.querySelector('[data-sketch-form]');

    const map = controller.map;
    map.createPane(PANE);
    // Au-dessus des zones et des chemins (400), sous les marqueurs (600).
    map.getPane(PANE).style.zIndex = 450;
    this.renderer = L.canvas({ pane: PANE, padding: 0.5 });

    this.onRootClick = (event) => this.handleRootClick(event);
    this.onRootChange = (event) => this.handleRootChange(event);
    this.onSubmit = (event) => this.submitForm(event);
    this.onToolbarClick = (event) => this.handleToolbarClick(event);
    this.root.addEventListener('click', this.onRootClick);
    this.root.addEventListener('change', this.onRootChange);
    this.form?.addEventListener('submit', this.onSubmit);
    this.toolbar?.addEventListener('click', this.onToolbarClick);

    this.refreshList();
  }

  destroy() {
    this.root?.removeEventListener('click', this.onRootClick);
    this.root?.removeEventListener('change', this.onRootChange);
    this.form?.removeEventListener('submit', this.onSubmit);
    this.toolbar?.removeEventListener('click', this.onToolbarClick);
  }

  // ── Adresses et requêtes ──────────────────────────────────────────────────

  url(kind, id) {
    const template = this.root.dataset[kind];
    return id == null ? template : template.replace('__ID__', encodeURIComponent(id));
  }

  async send(url, method = 'GET', body = null, extra = {}) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    return fetch(url, {
      method,
      credentials: 'same-origin',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': token || '' },
      body: body ? JSON.stringify(body) : undefined,
      ...extra,
    });
  }

  // ── Visibilité (préférence locale) ────────────────────────────────────────

  readHidden() {
    try {
      return new Set(JSON.parse(window.localStorage.getItem(HIDDEN_KEY) || '[]').map(String));
    } catch (_error) {
      return new Set();
    }
  }

  writeHidden() {
    try {
      window.localStorage.setItem(HIDDEN_KEY, JSON.stringify([...this.hidden]));
    } catch (_error) {
      // Sans stockage, l'affichage vaut pour la visite en cours.
    }
  }

  isVisible(id) {
    return !this.hidden.has(String(id));
  }

  async setVisible(id, visible) {
    id = String(id);
    if (visible) this.hidden.delete(id);
    else this.hidden.add(id);
    this.writeHidden();
    if (!visible && this.activeId === id) this.deactivate();

    const box = this.list?.querySelector(`[data-sketch-id="${CSS.escape(id)}"] [data-sketch-visible]`);
    if (box) box.checked = visible;

    if (!visible) {
      this.loaded.get(id)?.group.remove();
      return;
    }
    const sketch = await this.load(id);
    if (sketch && this.isVisible(id)) sketch.group.addTo(this.c.map);
  }

  // ── Chargement et rendu ───────────────────────────────────────────────────

  async refreshList() {
    const response = await this.send(this.url('sketchesUrl'));
    if (!response.ok) return;
    this.summaries = await response.json();
    this.renderList();
    const ids = new Set(this.summaries.map((s) => String(s.id)));
    // Un dessin supprimé ailleurs quitte la carte.
    [...this.loaded.keys()].forEach((id) => {
      if (!ids.has(id)) this.unload(id);
    });
    await Promise.all(
      this.summaries.filter((s) => this.isVisible(s.id)).map((s) => this.setVisible(s.id, true))
    );
  }

  async load(id, { force = false } = {}) {
    id = String(id);
    if (this.loaded.has(id) && !force) return this.loaded.get(id);
    const response = await this.send(this.url('sketchUrl', id));
    if (!response.ok) return null;
    const data = await response.json();

    let sketch = this.loaded.get(id);
    if (!sketch) {
      sketch = { id, group: L.layerGroup(), layers: new Map() };
      this.loaded.set(id, sketch);
    }
    sketch.strokes = Array.isArray(data.strokes) ? data.strokes : [];
    sketch.lockVersion = data.lock_version;
    this.redraw(sketch);
    return sketch;
  }

  unload(id) {
    if (this.activeId === id) this.deactivate();
    this.loaded.get(id)?.group.remove();
    this.loaded.delete(id);
  }

  // Tous les halos d'abord, puis tous les traits : un trait qui en croise un
  // autre ne le coupe pas d'une bande sombre.
  redraw(sketch) {
    sketch.group.clearLayers();
    sketch.layers.clear();
    const pairs = sketch.strokes.map((stroke) => [stroke.id, this.strokeLayers(stroke)]);
    pairs.forEach(([, [halo]]) => sketch.group.addLayer(halo));
    pairs.forEach(([strokeId, layers]) => {
      sketch.group.addLayer(layers[1]);
      sketch.layers.set(strokeId, layers);
    });
  }

  strokeLayers(stroke) {
    // Un point seul (un « . ») : deux fois le même point, que les bouts ronds
    // dessinent en pastille.
    const points = stroke.points.length === 1 ? [stroke.points[0], stroke.points[0]] : stroke.points;
    const width = Number(stroke.width) || 3;
    const options = {
      renderer: this.renderer,
      interactive: false,
      smoothFactor: 0.5,
      lineCap: 'round',
      lineJoin: 'round',
    };
    return [
      L.polyline(points, { ...options, color: HALO, opacity: 0.5, weight: width + 2.5 }),
      L.polyline(points, { ...options, color: INK, opacity: 1, weight: width }),
    ];
  }

  // ── Panneau ───────────────────────────────────────────────────────────────

  renderList() {
    if (!this.list) return;
    const rows = [];
    let folder;
    this.summaries.forEach((sketch) => {
      if (sketch.folder && sketch.folder !== folder) {
        rows.push(
          `<li class="px-2 pt-2 pb-0.5 text-xs font-medium text-stone-500" data-sketch-folder="${escapeHtml(sketch.folder)}">` +
            `<span aria-hidden="true">▸ </span>${escapeHtml(sketch.folder)}</li>`
        );
      }
      folder = sketch.folder;
      const id = String(sketch.id);
      const active = id === this.activeId;
      rows.push(
        `<li class="flex items-center gap-2${sketch.folder ? ' pl-3' : ''}" data-sketch-id="${id}">` +
          `<input type="checkbox" data-sketch-visible class="h-4 w-4 rounded border-stone-300 text-4s-main focus:ring-teal-400"` +
          ` aria-label="Afficher ${escapeHtml(sketch.name)}"${this.isVisible(id) ? ' checked' : ''}>` +
          `<button type="button" data-sketch-action="activate" aria-current="${active}"` +
          ` class="flex min-w-0 flex-1 items-center gap-1 rounded-lg px-2 py-1.5 text-left text-sm text-stone-600 hover:bg-stone-50${active ? ` ${ACTIVE_CLASSES.join(' ')}` : ''}"` +
          ` title="Dessiner dans « ${escapeHtml(sketch.name)} »">` +
          `<span class="truncate">${escapeHtml(sketch.name)}</span>` +
          `<span class="ml-auto text-[0.65rem] tabular-nums text-stone-400" data-sketch-count>${sketch.strokes_count}</span></button>` +
          `<button type="button" data-sketch-action="edit" class="flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-lg text-stone-400 hover:bg-stone-100 hover:text-stone-600"` +
          ` aria-label="Renommer ou ranger ${escapeHtml(sketch.name)}" title="Renommer, changer de dossier, supprimer">` +
          `<svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">` +
          `<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></svg></button>` +
          `</li>`
      );
    });
    this.list.innerHTML = rows.join('');
    this.empty?.classList.toggle('hidden', this.summaries.length > 0);

    const folders = [...new Set(this.summaries.map((s) => s.folder).filter(Boolean))];
    const datalist = this.root.querySelector('[data-sketch-folders]');
    if (datalist) datalist.innerHTML = folders.map((f) => `<option value="${escapeHtml(f)}"></option>`).join('');
  }

  handleRootChange(event) {
    const box = event.target.closest('[data-sketch-visible]');
    if (!box) return;
    this.setVisible(box.closest('[data-sketch-id]').dataset.sketchId, box.checked);
  }

  handleRootClick(event) {
    const button = event.target.closest('[data-sketch-action]');
    if (!button) return;
    const id = button.closest('[data-sketch-id]')?.dataset.sketchId;
    switch (button.dataset.sketchAction) {
      case 'new':
        return this.openForm(null);
      case 'edit':
        return this.openForm(id);
      case 'cancel-form':
        return this.closeForm();
      case 'delete':
        return this.remove(this.form.dataset.sketchId);
      case 'activate':
        return this.activeId === id ? this.deactivate() : this.activate(id);
      default:
        return undefined;
    }
  }

  openForm(id) {
    if (!this.form) return;
    const sketch = this.summaries.find((s) => String(s.id) === String(id));
    this.form.dataset.sketchId = sketch ? String(sketch.id) : '';
    this.form.elements.name.value = sketch?.name || '';
    this.form.elements.folder.value = sketch?.folder || '';
    this.form.querySelector('[data-sketch-action="delete"]')?.classList.toggle('hidden', !sketch);
    this.formError('');
    this.form.classList.remove('hidden');
    this.form.elements.name.focus();
  }

  closeForm() {
    this.form?.classList.add('hidden');
  }

  formError(message) {
    const error = this.form?.querySelector('[data-sketch-form-error]');
    if (!error) return;
    error.textContent = message;
    error.classList.toggle('hidden', !message);
  }

  async submitForm(event) {
    event.preventDefault();
    const id = this.form.dataset.sketchId;
    const body = { map_sketch: { name: this.form.elements.name.value, folder: this.form.elements.folder.value } };
    const response = id
      ? await this.send(this.url('sketchUrl', id), 'PATCH', body)
      : await this.send(this.url('sketchesUrl'), 'POST', body);
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      this.formError((data.errors || ["L'enregistrement a échoué."]).join(' '));
      return;
    }
    this.closeForm();
    // Un renommage fait avancer la version : le dessin chargé la suit, sinon
    // son prochain enregistrement serait refusé comme « modifié ailleurs ».
    const sketch = this.loaded.get(String(data.id));
    if (sketch) sketch.lockVersion = data.lock_version;
    await this.refreshList();
    if (!id) this.activate(String(data.id));
    else this.updateToolbarName();
  }

  async remove(id) {
    const sketch = this.summaries.find((s) => String(s.id) === String(id));
    if (!sketch) return;
    if (!window.confirm(`Supprimer « ${sketch.name} » ? Ses traits disparaîtront de la carte.`)) return;
    const response = await this.send(this.url('sketchUrl', id), 'DELETE');
    if (!response.ok) {
      this.formError("La suppression a échoué.");
      return;
    }
    this.closeForm();
    this.unload(String(id));
    this.hidden.delete(String(id));
    this.writeHidden();
    await this.refreshList();
  }

  // ── Dessin actif ──────────────────────────────────────────────────────────

  async activate(id) {
    id = String(id);
    if (this.activeId && this.activeId !== id) this.deactivate();
    // Un dessin masqué ne s'édite pas à l'aveugle : on le rallume.
    await this.setVisible(id, true);
    if (!this.loaded.has(id)) {
      this.c.showNotice("Ce dessin n'a pas pu être chargé.");
      return;
    }
    this.activeId = id;
    // La barre Geoman et la barre de dessin occupent la même place : on range
    // la première, et ses outils, le temps de dessiner.
    this.c.disableTools?.();
    if (this.c.hasToolbarTarget) {
      this.c.toolbarTarget.classList.add('hidden');
      this.c.toolbarTarget.classList.remove('flex');
    }
    this.toolbar?.classList.remove('hidden');
    this.toolbar?.classList.add('flex');
    this.updateToolbarName();
    this.renderList();
  }

  // `restoreLayer: false` quand c'est le choix d'une couche qui met fin au
  // dessin : le contrôleur est déjà en train de rétablir sa barre.
  deactivate({ restoreLayer = true } = {}) {
    if (!this.activeId) return;
    this.activeId = null;
    this.toolbar?.classList.add('hidden');
    this.toolbar?.classList.remove('flex');
    this.renderList();
    if (restoreLayer && this.c.activeLayerId) this.c.setActiveLayer(this.c.activeLayerId, this.c.activeLayerKind);
  }

  // Le contrôleur prévient quand une couche devient active : on quitte le dessin.
  onLayerActivated() {
    this.deactivate({ restoreLayer: false });
  }

  updateToolbarName() {
    const label = this.toolbar?.querySelector('[data-sketch-toolbar-name]');
    const sketch = this.summaries.find((s) => String(s.id) === this.activeId);
    if (label) label.textContent = sketch?.name || '';
  }

  handleToolbarClick(event) {
    const button = event.target.closest('[data-sketch-tool]');
    if (button?.dataset.sketchTool === 'done') this.deactivate();
  }
}
