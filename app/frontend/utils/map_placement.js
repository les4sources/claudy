// Le mode Placement des plantes (epic #348, phase 7).
//
// ~95 plantes, 7 placées : l'essentiel du travail est de poser des points, sur
// le terrain, téléphone à la main. Le geste doit donc s'enchaîner : choisir une
// plante dans le tiroir, toucher la carte (ou « Je suis devant »), et la
// suivante est déjà choisie. Une plante placée se corrige en la glissant.
//
// Ce module tient l'état du placement ; le contrôleur `map` lui prête sa carte,
// ses cibles et ses méthodes (`loadLayer`, `selectFeature`, `findFeatureLayer`).

import L from '~/utils/leaflet_global';

// Au-delà, une position GPS est trop floue pour un arbre : on prévient, et il
// faut toucher une seconde fois pour forcer.
export const GPS_MAX_ACCURACY = 25;
// La montre GPS s'arrête d'elle-même : la meilleure position est gardée.
const GPS_WATCH_MS = 45000;
const GPS_COLOR = '#1F5F4A';
const GPS_WEAK_COLOR = '#C97B3D';
// Marge pour l'horloge : une position datée d'une seconde avant l'appui est
// bien celle qu'on vient de demander.
const GPS_STALE_SLACK_MS = 1000;

// Malgré `maximumAge: 0`, un téléphone (Safari surtout) renvoie d'abord sa
// dernière position en cache : celle de l'appui précédent, souvent précise.
// Comme on garde la meilleure position vue, elle bloquait toutes les
// suivantes et on restait « relocalisé » au premier endroit. On l'écarte.
export function isFreshFix(position, startedAt) {
  return !position?.timestamp || position.timestamp >= startedAt - GPS_STALE_SLACK_MS;
}

export class PlantPlacement {
  constructor(controller) {
    this.c = controller;
    this.target = null;
    this.last = null;
    this.fix = null;
    this.watchId = null;
    this.busy = false;
    this.onKeydown = (event) => {
      if (event.key === 'Escape' && this.target) {
        event.preventDefault();
        this.cancel();
      }
    };
    document.addEventListener('keydown', this.onKeydown);
    if (this.c.hasUnplacedFrameTarget) {
      this.c.unplacedFrameTarget.addEventListener('turbo:frame-load', () => this.onListLoad());
      this.c.unplacedFrameTarget.addEventListener('turbo:before-frame-render', (event) => this.keepSearchFocus(event));
    }
  }

  get map() {
    return this.c.map;
  }

  get active() {
    return Boolean(this.target);
  }

  get wide() {
    return window.matchMedia('(min-width: 768px)').matches;
  }

  destroy() {
    document.removeEventListener('keydown', this.onKeydown);
    this.stopGps();
  }

  // ── Le tiroir ────────────────────────────────────────────────────────────

  open() {
    if (!this.c.hasPlacementDrawerTarget) return;
    this.c.placementDrawerTarget.classList.remove('hidden');
    this.c.placementDrawerTarget.classList.add('flex');
    this.showPlantsLayer();
    const frame = this.c.unplacedFrameTarget;
    if (!frame.getAttribute('src')) frame.src = this.c.unplacedUrlValue;
    else frame.reload();
    // Sur un téléphone, la fiche plein écran et le panneau des couches
    // cacheraient la carte : on pose au doigt, il faut la voir.
    if (!this.wide) {
      this.c.closePanel();
      this.c.collapsePanelOnPhone();
    }
    this.c.updateModeBar();
  }

  // Une couche Plantes masquée cacherait les points qu'on pose.
  showPlantsLayer() {
    const toggle = this.c.layerToggleTargets.find((t) => this.c.layerKinds?.[t.dataset.layerId] === 'plants');
    if (toggle && !toggle.checked) {
      toggle.checked = true;
      toggle.dispatchEvent(new Event('change'));
    }
  }

  // La zone filtrée dans le tiroir, reprise par « Nouvelle plante ».
  get zone() {
    if (!this.drawerOpen) return null;
    return this.c.unplacedFrameTarget.querySelector('select[name="zone"]')?.value || null;
  }

  close() {
    this.cancel();
    if (!this.c.hasPlacementDrawerTarget) return;
    this.c.placementDrawerTarget.classList.add('hidden');
    this.c.placementDrawerTarget.classList.remove('flex');
    this.c.updateModeBar();
  }

  get drawerOpen() {
    return this.c.hasPlacementDrawerTarget && !this.c.placementDrawerTarget.classList.contains('hidden');
  }

  items() {
    return this.c.hasUnplacedFrameTarget
      ? [...this.c.unplacedFrameTarget.querySelectorAll('[data-unplaced-item]')]
      : [];
  }

  onListLoad() {
    const list = this.c.unplacedFrameTarget.querySelector('[data-unplaced-list]');
    if (list) this.setCount(Number(list.dataset.unplacedTotal));
    this.markSelection();
  }

  // Sur iPad et iPhone, remplacer le champ de recherche à chaque lettre ferme
  // le clavier. Tant qu'un champ des filtres a le focus, on ne remplace donc
  // que les résultats : le formulaire, vivant, ne quitte jamais la page.
  keepSearchFocus(event) {
    const form = this.c.unplacedFrameTarget.querySelector('form');
    if (!form?.contains(document.activeElement)) return;
    event.detail.render = (current, next) => {
      const list = current.querySelector('[data-unplaced-list]');
      const nextList = next.querySelector('[data-unplaced-list]');
      const results = current.querySelector('[data-unplaced-results]');
      const nextResults = next.querySelector('[data-unplaced-results]');
      if (!list || !nextList || !results || !nextResults) {
        current.replaceChildren(...next.childNodes);
        return;
      }
      [...nextList.attributes].forEach(({ name, value }) => list.setAttribute(name, value));
      results.replaceWith(nextResults);
    };
  }

  markSelection() {
    const id = this.target?.mode === 'place' ? String(this.target.id) : null;
    this.items().forEach((item) => item.setAttribute('aria-pressed', String(item.dataset.plantId === id)));
    const selected = this.items().find((item) => item.dataset.plantId === id);
    selected?.scrollIntoView({ block: 'nearest' });
  }

  // Recharge la liste en gardant ses filtres (la frame garde l'URL de sa
  // dernière navigation) et la plante choisie.
  reloadList(selectedId) {
    if (!this.c.hasUnplacedFrameTarget || !this.drawerOpen) return;
    const frame = this.c.unplacedFrameTarget;
    const url = new URL(frame.getAttribute('src') || this.c.unplacedUrlValue, window.location.origin);
    if (selectedId) url.searchParams.set('selected', selectedId);
    else url.searchParams.delete('selected');
    frame.src = url.pathname + url.search;
  }

  setCount(count) {
    if (!Number.isFinite(count)) return;
    this.c.unplacedCountTargets.forEach((el) => {
      el.textContent = String(count);
      el.classList.toggle('hidden', count === 0);
    });
  }

  bumpCount(delta) {
    const current = Number(this.c.unplacedCountTargets[0]?.textContent);
    if (Number.isFinite(current)) this.setCount(Math.max(0, current + delta));
    this.reloadList(this.target?.mode === 'place' ? this.target.id : null);
  }

  // ── Choisir une plante à placer ─────────────────────────────────────────

  pick({ plantId, plantName }, { fromPanel = false } = {}) {
    this.finishMove();
    this.target = { id: plantId, name: plantName, mode: 'place' };
    this.fix = null;
    this.stopGps();
    if (fromPanel && !this.wide) this.c.closePanel();
    this.markSelection();
    this.showBanner();
  }

  // ── Déplacer une plante placée ──────────────────────────────────────────

  startMove({ plantId, plantName, featureId }, { gps = false } = {}) {
    const found = this.c.findFeatureLayer(String(featureId));
    if (!found?.layer?.getLatLng) {
      this.c.showNotice('Le point de cette plante est introuvable sur la carte.');
      return;
    }
    this.finishMove();
    this.stopGps();
    this.fix = null;
    const { layer } = found;
    this.target = { id: plantId, name: plantName, mode: 'move', featureId: String(featureId), layer };
    this.markSelection();
    if (!this.wide && this.c.hasPanelContainerTarget) this.c.panelContainerTarget.classList.add('hidden');

    this.map.setView(layer.getLatLng(), Math.max(this.map.getZoom(), 19));
    if (layer.dragging) {
      layer.dragging.enable();
      layer.getElement()?.classList.add('map-plant-pin-wrapper--moving');
      this.onDragEnd = () => this.submit(layer.getLatLng());
      layer.on('dragend', this.onDragEnd);
    }
    this.showBanner();
    if (gps) this.startGps();
  }

  finishMove() {
    const layer = this.target?.mode === 'move' ? this.target.layer : null;
    if (!layer) return;
    layer.dragging?.disable();
    layer.getElement()?.classList.remove('map-plant-pin-wrapper--moving');
    if (this.onDragEnd) layer.off('dragend', this.onDragEnd);
    this.onDragEnd = null;
  }

  // ── La carte touchée ────────────────────────────────────────────────────

  onMapClick(event) {
    if (!this.target || !event?.latlng) return;
    // En déplacement, toucher la carte y amène le point : plus sûr au doigt que
    // de glisser une pastille de 22 px.
    if (this.target.mode === 'move') this.target.layer.setLatLng(event.latlng);
    this.submit(event.latlng);
  }

  cancel() {
    if (!this.target) {
      this.hideBanner();
      return;
    }
    const { mode, featureId } = this.target;
    const layerId = this.target.layer?.layerId;
    this.finishMove();
    this.target = null;
    this.stopGps();
    this.hideBanner();
    this.markSelection();
    // Un glisser abandonné en cours : la couche rechargée remet le point à sa
    // place enregistrée, et la fiche revient.
    if (mode === 'move') {
      if (layerId) this.c.loadLayer(layerId).then(() => this.c.highlightSelection());
      this.c.selectFeature(featureId);
    }
  }

  // ── L'enregistrement ────────────────────────────────────────────────────

  async submit(latlng) {
    if (!this.target || this.busy) return;
    this.busy = true;
    const target = this.target;
    this.setHint('Enregistrement…');
    try {
      const response = await this.post(this.c.placeUrl(target.id), { latitude: latlng.lat, longitude: latlng.lng });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        this.setHint(data.error || "L'enregistrement a échoué : réessayez.", true);
        return;
      }
      this.stopGps();
      this.finishMove();
      await this.c.loadLayer(data.layer_id);
      this.setCount(data.remaining);

      if (target.mode === 'move') {
        this.target = null;
        this.hideBanner();
        this.c.selectFeature(data.map_feature_id);
        this.c.showNotice(`${target.name} : nouvelle position enregistrée.`);
        return;
      }

      this.last = { id: target.id, name: target.name, featureId: data.map_feature_id, layerId: data.layer_id };
      const next = this.nextItem(target.id);
      // Sur grand écran, la fiche s'ouvre à droite sans gêner ; sur un
      // téléphone elle couvrirait la carte : la ligne « placé » y mène.
      if (this.wide) this.c.selectFeature(data.map_feature_id);
      else this.c.highlightSelection();
      if (next) this.pick(next.dataset);
      else this.endQueue();
      this.showLast();
      this.reloadList(next?.dataset.plantId);
    } finally {
      this.busy = false;
    }
  }

  // La plante suivante dans la liste affichée (filtres compris), sinon la
  // précédente.
  nextItem(id) {
    const items = this.items();
    const index = items.findIndex((item) => item.dataset.plantId === String(id));
    const rest = items.filter((item) => item.dataset.plantId !== String(id));
    if (index === -1) return rest[0] || null;
    return items[index + 1] || rest[rest.length - 1] || null;
  }

  endQueue() {
    this.target = null;
    this.stopGps();
    this.markSelection();
    this.showBanner();
  }

  async undo() {
    const last = this.last;
    if (!last || this.busy) return;
    this.busy = true;
    try {
      const response = await this.post(this.c.unplaceUrl(last.id));
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        this.c.showNotice("L'annulation a échoué — rechargez la page.");
        return;
      }
      this.last = null;
      if (String(this.c.selectedFeatureId) === String(last.featureId)) this.c.closePanel();
      await this.c.loadLayer(last.layerId);
      this.setCount(data.remaining);
      this.pick({ plantId: String(last.id), plantName: last.name });
      this.reloadList(last.id);
    } finally {
      this.busy = false;
    }
  }

  openLast() {
    if (this.last) this.c.selectFeature(this.last.featureId);
  }

  adjustLast() {
    if (!this.last) return;
    const { id, name, featureId } = this.last;
    this.startMove({ plantId: id, plantName: name, featureId });
  }

  post(url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': token || '' },
      body: body ? JSON.stringify(body) : undefined,
    });
  }

  // ── « Je suis devant » ──────────────────────────────────────────────────
  //
  // `watchPosition` plutôt qu'une lecture unique : la première position d'un
  // téléphone est souvent à 50 m, elle s'affine en quelques secondes. On garde
  // la meilleure, on l'affiche avec son cercle d'incertitude, et c'est la
  // personne qui confirme.

  startGps() {
    if (!this.target) return;
    if (!navigator.geolocation) {
      this.setHint("Ce navigateur ne donne pas la position : touchez la carte à l'endroit de la plante.", true);
      return;
    }
    this.stopGps();
    this.fix = null;
    this.forceArmed = false;
    this.setHint('Recherche de la position… restez à côté de la plante.');
    this.renderGpsConfirm();
    this.gpsStartedAt = Date.now();
    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.onGpsFix(position),
      (error) => this.onGpsError(error),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 30000 }
    );
    this.watchTimer = setTimeout(() => this.stopWatch(), GPS_WATCH_MS);
  }

  onGpsFix(position) {
    if (!isFreshFix(position, this.gpsStartedAt)) return;
    const { latitude, longitude, accuracy } = position.coords;
    if (this.fix && accuracy > this.fix.accuracy) return;
    const first = !this.fix;
    this.fix = { lat: latitude, lng: longitude, accuracy };
    this.forceArmed = false;
    this.drawFix();
    if (first) this.map.setView([latitude, longitude], Math.max(this.map.getZoom(), 19));
    const precise = accuracy <= GPS_MAX_ACCURACY;
    this.setHint(
      precise
        ? `Position à ± ${Math.round(accuracy)} m : confirmez, ou attendez qu'elle s'affine.`
        : `Position encore floue (± ${Math.round(accuracy)} m) : attendez quelques secondes à découvert, ou touchez la carte.`,
      !precise
    );
    this.renderGpsConfirm();
  }

  onGpsError(error) {
    if (this.fix) return;
    this.stopGps();
    this.setHint(
      error?.code === 1
        ? 'Géolocalisation refusée : autorisez-la pour ce site, ou touchez la carte.'
        : 'Position introuvable : touchez la carte à l’endroit de la plante.',
      true
    );
  }

  confirmGps() {
    if (!this.fix) return;
    if (this.fix.accuracy > GPS_MAX_ACCURACY && !this.forceArmed) {
      this.forceArmed = true;
      this.renderGpsConfirm();
      return;
    }
    const latlng = { lat: this.fix.lat, lng: this.fix.lng };
    if (this.target?.mode === 'move') this.target.layer.setLatLng([latlng.lat, latlng.lng]);
    this.submit(latlng);
  }

  drawFix() {
    const { lat, lng, accuracy } = this.fix;
    const color = accuracy <= GPS_MAX_ACCURACY ? GPS_COLOR : GPS_WEAK_COLOR;
    if (!this.fixCircle) {
      this.fixCircle = L.circle([lat, lng], { radius: accuracy, color, weight: 1, fillOpacity: 0.12, interactive: false }).addTo(this.map);
      this.fixDot = L.circleMarker([lat, lng], { radius: 6, color: '#fff', weight: 2, fillColor: color, fillOpacity: 1, interactive: false }).addTo(this.map);
    } else {
      this.fixCircle.setLatLng([lat, lng]).setRadius(accuracy).setStyle({ color });
      this.fixDot.setLatLng([lat, lng]).setStyle({ fillColor: color });
    }
  }

  stopWatch() {
    if (this.watchId !== null) navigator.geolocation?.clearWatch(this.watchId);
    this.watchId = null;
    clearTimeout(this.watchTimer);
  }

  stopGps() {
    this.stopWatch();
    this.fix = null;
    this.forceArmed = false;
    if (this.fixCircle) this.map?.removeLayer(this.fixCircle);
    if (this.fixDot) this.map?.removeLayer(this.fixDot);
    this.fixCircle = null;
    this.fixDot = null;
    this.renderGpsConfirm();
  }

  // ── Le bandeau ──────────────────────────────────────────────────────────

  showBanner() {
    if (!this.c.hasPlacementBannerTarget) return;
    const banner = this.c.placementBannerTarget;
    banner.classList.remove('hidden');
    this.map.getContainer().style.cursor = this.target ? 'crosshair' : '';

    const message = this.c.placementMessageTarget;
    message.replaceChildren();
    if (this.target) {
      const verb = this.target.mode === 'move' ? 'Glissez ou touchez la carte pour déplacer ' : 'Touchez la carte pour placer ';
      const name = document.createElement('strong');
      name.className = 'font-semibold text-forest';
      name.textContent = this.target.name;
      message.append(verb, name);
      this.setHint(this.target.mode === 'move' ? 'Échap ou × pour annuler.' : 'Échap ou × pour arrêter. La suivante sera choisie d’office.');
    } else {
      message.textContent = 'Plus aucune plante dans cette liste.';
      this.setHint('Changez de zone ou de recherche dans le tiroir, ou fermez-le.');
    }
    this.c.placementGpsTarget.classList.toggle('hidden', !this.target);
    this.c.placementGpsTarget.textContent = this.target?.mode === 'move' ? 'Placer ici (GPS)' : 'Je suis devant';
    this.renderGpsConfirm();
  }

  hideBanner() {
    this.last = null;
    if (this.c.hasPlacementLastTarget) this.c.placementLastTarget.classList.add('hidden');
    if (this.c.hasPlacementBannerTarget) this.c.placementBannerTarget.classList.add('hidden');
    if (this.map) this.map.getContainer().style.cursor = '';
  }

  setHint(text, warn = false) {
    if (!this.c.hasPlacementHintTarget) return;
    this.c.placementHintTarget.textContent = text;
    this.c.placementHintTarget.classList.toggle('text-ember', warn);
    this.c.placementHintTarget.classList.toggle('text-stone-500', !warn);
  }

  renderGpsConfirm() {
    if (!this.c.hasPlacementGpsConfirmTarget) return;
    const button = this.c.placementGpsConfirmTarget;
    const fix = this.target ? this.fix : null;
    button.classList.toggle('hidden', !fix);
    if (!fix) return;
    const meters = Math.round(fix.accuracy);
    const precise = fix.accuracy <= GPS_MAX_ACCURACY;
    button.textContent = precise
      ? `Placer ici · ± ${meters} m`
      : this.forceArmed
        ? `Toucher encore pour forcer (± ${meters} m)`
        : `Précision faible (± ${meters} m)`;
    button.classList.toggle('bg-forest', precise);
    button.classList.toggle('bg-ember', !precise);
  }

  showLast() {
    if (!this.c.hasPlacementLastTarget) return;
    const row = this.c.placementLastTarget;
    row.classList.toggle('hidden', !this.last);
    if (this.last) this.c.placementLastMessageTarget.textContent = `${this.last.name} placée.`;
    this.showBanner();
  }

  dismissLast() {
    if (!this.target) {
      this.hideBanner();
      return;
    }
    this.last = null;
    if (this.c.hasPlacementLastTarget) this.c.placementLastTarget.classList.add('hidden');
  }
}
