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
const PEN_WIDTH = 3;
// Les plafonds du modèle `MapSketch` : les dépasser serait refusé au serveur.
const MAX_POINTS = 5000;
const MAX_STROKES = 2000;
const SAVE_DELAY = 500;
// Écart toléré au trait réel par la simplification, en pixels écran.
const SIMPLIFY_TOLERANCE = 0.75;

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

    this.setupDrawing();
    this.refreshList();
  }

  destroy() {
    this.root?.removeEventListener('click', this.onRootClick);
    this.root?.removeEventListener('change', this.onRootChange);
    this.form?.removeEventListener('submit', this.onSubmit);
    this.toolbar?.removeEventListener('click', this.onToolbarClick);
    document.removeEventListener('keydown', this.onKeydown);
    window.removeEventListener('beforeunload', this.onBeforeUnload);
    // La page s'en va (navigation Turbo) avec un trait pas encore parti : on
    // l'envoie quand même, `keepalive` survit au changement de page.
    if (this.dirty && this.dirtySketch) {
      clearTimeout(this.saveTimer);
      this.send(this.url('sketchStrokesUrl', this.dirtySketch.id), 'PATCH',
        { strokes: this.dirtySketch.strokes, lock_version: this.dirtySketch.lockVersion }, { keepalive: true });
    }
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
    this.undoStack = [];
    this.penSeen = false;
    this.setStatus(this.dirty ? 'saving' : 'saved');
    // Activer un dessin, c'est vouloir y dessiner : le stylo est pris d'office,
    // la main est à un geste.
    this.setTool('pen');
  }

  // `restoreLayer: false` quand c'est le choix d'une couche qui met fin au
  // dessin : le contrôleur est déjà en train de rétablir sa barre.
  deactivate({ restoreLayer = true } = {}) {
    if (!this.activeId) return;
    this.cancelStroke();
    this.setTool('hand');
    this.flushSave();
    this.undoStack = [];
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
    const status = event.target.closest('[data-sketch-status]');
    if (status && !status.disabled) {
      this.save();
      return;
    }
    const tool = event.target.closest('[data-sketch-tool]')?.dataset.sketchTool;
    if (tool === 'done') this.deactivate();
    else if (tool === 'undo') this.undo();
    else if (tool) this.setTool(tool);
  }

  // ── Outils : stylo, gomme, main ───────────────────────────────────────────
  //
  // Un calque de saisie transparent couvre la carte quand le stylo ou la gomme
  // est pris : `touch-action: none` empêche le navigateur de faire défiler ou
  // zoomer la page sous le trait, et la carte est figée (glisser, zoom à la
  // molette, au double-clic, au pincement). La main retire le calque et rend la
  // carte.

  setupDrawing() {
    this.tool = 'hand';
    this.undoStack = [];
    this.pointerId = null;
    this.current = null;
    this.dirty = false;
    this.saving = false;
    this.lockedHandlers = [];

    const map = this.c.map;
    this.capture = L.DomUtil.create('div', 'map-sketch-capture', map.getContainer());
    L.DomEvent.disableClickPropagation(this.capture);
    L.DomEvent.disableScrollPropagation(this.capture);
    this.capture.addEventListener('pointerdown', (event) => this.onPointerDown(event));
    this.capture.addEventListener('pointermove', (event) => this.onPointerMove(event));
    this.capture.addEventListener('pointerup', (event) => this.onPointerUp(event));
    this.capture.addEventListener('pointercancel', (event) => this.onPointerUp(event, { cancel: true }));
    // Le menu du clic long (iPad, Android) interromprait le trait.
    this.capture.addEventListener('contextmenu', (event) => event.preventDefault());

    this.onKeydown = (event) => {
      if (!this.activeId || !(event.metaKey || event.ctrlKey) || event.shiftKey) return;
      if (String(event.key || '').toLowerCase() !== 'z') return;
      if (event.target.closest?.('input, textarea, [contenteditable]')) return;
      event.preventDefault();
      this.undo();
    };
    document.addEventListener('keydown', this.onKeydown);
    this.onBeforeUnload = (event) => {
      if (!this.dirty && !this.saving) return;
      this.flushSave();
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', this.onBeforeUnload);
  }

  setTool(tool) {
    const drawing = Boolean(this.activeId) && (tool === 'pen' || tool === 'eraser');
    this.tool = drawing ? tool : 'hand';
    if (!drawing) this.cancelStroke();
    if (drawing) this.lockMap();
    else this.unlockMap();
    this.capture.classList.toggle('map-sketch-capture--on', drawing);
    this.capture.classList.toggle('map-sketch-capture--eraser', this.tool === 'eraser');

    this.toolbar?.querySelectorAll('[data-sketch-tool]').forEach((button) => {
      const name = button.dataset.sketchTool;
      if (!['pen', 'eraser', 'hand'].includes(name)) return;
      const on = name === this.tool;
      button.setAttribute('aria-pressed', String(on));
      button.classList.toggle('bg-forest-tint', on);
      button.classList.toggle('text-forest', on);
    });
    this.updateUndoButton();
  }

  // Les gestionnaires de la carte coupés par le stylo, rendus tels quels par la
  // main (un gestionnaire déjà coupé ailleurs le reste).
  lockMap() {
    if (this.lockedHandlers.length) return;
    const map = this.c.map;
    ['dragging', 'touchZoom', 'doubleClickZoom', 'scrollWheelZoom', 'boxZoom', 'keyboard', 'tap'].forEach((name) => {
      const handler = map[name];
      if (handler?.enabled?.()) {
        handler.disable();
        this.lockedHandlers.push(handler);
      }
    });
  }

  unlockMap() {
    this.lockedHandlers.forEach((handler) => handler.enable());
    this.lockedHandlers = [];
  }

  activeSketch() {
    return this.activeId ? this.loaded.get(this.activeId) : null;
  }

  // ── Saisie au pointeur (stylet, doigt, souris) ────────────────────────────

  onPointerDown(event) {
    const sketch = this.activeSketch();
    if (!sketch || this.tool === 'hand') return;
    if (event.pointerType === 'pen') this.penSeen = true;
    // La paume : une fois le stylet utilisé, le doigt ne dessine plus (il ne
    // fait rien, la main sert à déplacer la carte).
    if (event.pointerType === 'touch' && this.penSeen) return;
    if (this.pointerId !== null) return;
    if (event.pointerType === 'mouse' && event.button !== 0) return;

    event.preventDefault();
    event.stopPropagation();
    this.capture.setPointerCapture?.(event.pointerId);
    this.pointerId = event.pointerId;
    const point = this.c.map.mouseEventToContainerPoint(event);
    if (this.tool === 'pen') this.startStroke(sketch, point);
    else this.eraseAt(sketch, point, event.pointerType);
  }

  onPointerMove(event) {
    if (event.pointerId !== this.pointerId) return;
    event.preventDefault();
    const sketch = this.activeSketch();
    if (!sketch) return;
    // Les points intermédiaires que le navigateur a regroupés : un trait
    // rapide au stylet reste une courbe, pas une ligne brisée.
    const events = event.getCoalescedEvents?.() || [];
    (events.length ? events : [event]).forEach((e) => {
      const point = this.c.map.mouseEventToContainerPoint(e);
      if (this.tool === 'pen') this.extendStroke(sketch, point);
      else if (this.tool === 'eraser') this.eraseAt(sketch, point, event.pointerType);
    });
  }

  onPointerUp(event, { cancel = false } = {}) {
    if (event.pointerId !== this.pointerId) return;
    this.pointerId = null;
    this.capture.releasePointerCapture?.(event.pointerId);
    const sketch = this.activeSketch();
    if (!sketch || !this.current) return;
    // Un trait interrompu par le système (appel, geste de l'OS) est gardé tel
    // quel : il a été voulu jusque-là.
    if (cancel && this.current.px.length < 2) this.cancelStroke();
    else this.finishStroke(sketch);
  }

  // ── Stylo ─────────────────────────────────────────────────────────────────

  startStroke(sketch, point) {
    if (sketch.strokes.length >= MAX_STROKES) {
      this.c.showNotice(`Ce dessin est plein (${MAX_STROKES} traits) : créez-en un autre.`);
      return;
    }
    const latlng = this.c.map.containerPointToLatLng(point);
    const [halo, line] = this.strokeLayers({ points: [[latlng.lat, latlng.lng]], width: PEN_WIDTH });
    sketch.group.addLayer(halo);
    sketch.group.addLayer(line);
    this.current = { px: [point], latlngs: [latlng], halo, line };
  }

  extendStroke(sketch, point) {
    const current = this.current;
    if (!current) return;
    // Moins d'un pixel et demi : du bruit de capteur, pas un geste.
    if (point.distanceTo(current.px[current.px.length - 1]) < 1.5) return;
    if (current.px.length >= MAX_POINTS) {
      this.finishStroke(sketch);
      this.startStroke(sketch, point);
      return;
    }
    current.px.push(point);
    current.latlngs.push(this.c.map.containerPointToLatLng(point));
    current.halo.setLatLngs(current.latlngs);
    current.line.setLatLngs(current.latlngs);
  }

  finishStroke(sketch) {
    const current = this.current;
    this.current = null;
    if (!current) return;
    sketch.group.removeLayer(current.halo);
    sketch.group.removeLayer(current.line);

    // Lissage : Douglas-Peucker en pixels ÉCRAN au zoom du geste. Un trait fait
    // de près garde ses détails, un trait fait de loin ne s'encombre pas de
    // points que personne ne verra.
    const keep = simplifyIndexes(current.px, SIMPLIFY_TOLERANCE);
    const points = keep.map((i) => [round7(current.latlngs[i].lat), round7(current.latlngs[i].lng)]);
    const stroke = { id: shortId(), points, width: PEN_WIDTH };
    sketch.strokes.push(stroke);
    this.addStrokeLayers(sketch, stroke);
    this.pushUndo({ type: 'add', strokeId: stroke.id });
    this.markDirty(sketch);
  }

  cancelStroke() {
    const current = this.current;
    this.current = null;
    if (!current) return;
    current.halo.remove();
    current.line.remove();
  }

  addStrokeLayers(sketch, stroke) {
    const layers = this.strokeLayers(stroke);
    sketch.group.addLayer(layers[0]);
    sketch.group.addLayer(layers[1]);
    // Le halo repasse sous tous les traits (voir `redraw`).
    if (sketch.group._map) layers[0].bringToBack();
    sketch.layers.set(stroke.id, layers);
  }

  // ── Gomme : au contact, un tracé entier disparaît ─────────────────────────

  eraseAt(sketch, point, pointerType) {
    const map = this.c.map;
    // Un doigt est plus large qu'une pointe de stylet ou de souris.
    const reach = pointerType === 'touch' ? 16 : 10;
    const corner = L.point(reach + 6, reach + 6);
    const around = L.latLngBounds(
      map.containerPointToLatLng(point.subtract(corner)),
      map.containerPointToLatLng(point.add(corner))
    );

    for (let index = sketch.strokes.length - 1; index >= 0; index -= 1) {
      const stroke = sketch.strokes[index];
      if (!strokeBounds(stroke).intersects(around)) continue;
      const px = stroke.points.map(([lat, lng]) => map.latLngToContainerPoint([lat, lng]));
      const limit = reach + (Number(stroke.width) || PEN_WIDTH) / 2;
      const hit =
        px.length === 1
          ? point.distanceTo(px[0]) <= limit
          : px.some((p, i) => i > 0 && L.LineUtil.pointToSegmentDistance(point, px[i - 1], p) <= limit);
      if (!hit) continue;

      sketch.strokes.splice(index, 1);
      sketch.layers.get(stroke.id)?.forEach((layer) => sketch.group.removeLayer(layer));
      sketch.layers.delete(stroke.id);
      this.pushUndo({ type: 'erase', stroke, index });
      this.markDirty(sketch);
    }
  }

  // ── Annuler (pile locale au dessin actif) ─────────────────────────────────

  pushUndo(entry) {
    this.undoStack.push(entry);
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.updateUndoButton();
  }

  undo() {
    const sketch = this.activeSketch();
    const entry = this.undoStack.pop();
    this.updateUndoButton();
    if (!sketch || !entry) return;
    if (entry.type === 'add') {
      const index = sketch.strokes.findIndex((s) => s.id === entry.strokeId);
      if (index === -1) return;
      sketch.strokes.splice(index, 1);
    } else {
      sketch.strokes.splice(Math.min(entry.index, sketch.strokes.length), 0, entry.stroke);
    }
    this.redraw(sketch);
    this.markDirty(sketch);
  }

  updateUndoButton() {
    const button = this.toolbar?.querySelector('[data-sketch-tool="undo"]');
    if (button) button.disabled = !this.undoStack?.length;
  }

  // ── Enregistrement automatique ────────────────────────────────────────────
  //
  // 500 ms après le dernier geste, les tracés du dessin partent en bloc avec la
  // version lue. 409 : quelqu'un d'autre a écrit entre-temps, on recharge son
  // dessin (le geste local est perdu, on le dit). Toute autre erreur laisse le
  // dessin « à enregistrer » : l'indicateur devient un bouton « réessayer ».

  markDirty(sketch) {
    this.dirty = true;
    this.dirtySketch = sketch;
    const summary = this.summaries.find((s) => String(s.id) === sketch.id);
    if (summary) {
      summary.strokes_count = sketch.strokes.length;
      const count = this.list?.querySelector(`[data-sketch-id="${CSS.escape(sketch.id)}"] [data-sketch-count]`);
      if (count) count.textContent = String(sketch.strokes.length);
    }
    this.setStatus('saving');
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.save(), SAVE_DELAY);
  }

  flushSave() {
    if (!this.dirty) return;
    clearTimeout(this.saveTimer);
    this.save();
  }

  async save() {
    const sketch = this.dirtySketch;
    if (!this.dirty || !sketch) return;
    if (this.saving) {
      this.saveAgain = true;
      return;
    }
    clearTimeout(this.saveTimer);
    this.saving = true;
    this.saveAgain = false;
    this.dirty = false;
    this.setStatus('saving');

    let failed = false;
    try {
      const response = await this.send(this.url('sketchStrokesUrl', sketch.id), 'PATCH', {
        strokes: sketch.strokes,
        lock_version: sketch.lockVersion,
      });
      const data = await response.json().catch(() => ({}));
      if (response.ok) {
        sketch.lockVersion = data.lock_version;
      } else if (response.status === 409) {
        this.dirty = false;
        this.saveAgain = false;
        this.c.showNotice('Ce dessin a été modifié ailleurs : il vient d’être rechargé.');
        await this.load(sketch.id, { force: true });
        if (this.activeId === sketch.id) this.undoStack = [];
        this.updateUndoButton();
      } else {
        failed = true;
      }
    } catch (_error) {
      failed = true;
    } finally {
      this.saving = false;
    }

    if (failed) {
      this.dirty = true;
      this.setStatus('error');
    } else if (this.dirty || this.saveAgain) {
      this.save();
    } else {
      this.setStatus('saved');
    }
  }

  setStatus(state) {
    const status = this.toolbar?.querySelector('[data-sketch-status]');
    if (!status) return;
    status.textContent = { saved: 'Enregistré', saving: 'Enregistrement…', error: 'Erreur — réessayer' }[state];
    status.disabled = state !== 'error';
    status.classList.toggle('text-red-700', state === 'error');
    status.classList.toggle('underline', state === 'error');
    status.classList.toggle('text-stone-500', state !== 'error');
  }
}

// ── Utilitaires ─────────────────────────────────────────────────────────────

const boundsCache = new WeakMap();

function strokeBounds(stroke) {
  if (!boundsCache.has(stroke)) boundsCache.set(stroke, L.latLngBounds(stroke.points));
  return boundsCache.get(stroke);
}

function round7(value) {
  return Math.round(value * 1e7) / 1e7;
}

// Un identifiant court, unique dans un dessin (lettres, chiffres).
function shortId() {
  return Math.random().toString(36).slice(2, 8) + Date.now().toString(36).slice(-4);
}

// Douglas-Peucker itératif sur des points écran : les indices des points gardés.
export function simplifyIndexes(points, tolerance) {
  if (points.length <= 2) return points.map((_p, i) => i);
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];
  while (stack.length) {
    const [first, last] = stack.pop();
    let farthest = -1;
    let distance = tolerance;
    for (let i = first + 1; i < last; i += 1) {
      const d = L.LineUtil.pointToSegmentDistance(points[i], points[first], points[last]);
      if (d > distance) {
        distance = d;
        farthest = i;
      }
    }
    if (farthest !== -1) {
      keep[farthest] = 1;
      stack.push([first, farthest], [farthest, last]);
    }
  }
  return [...keep.keys()].filter((i) => keep[i]);
}
