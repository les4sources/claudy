// Les relevés de biodiversité sur la carte (epic #348, phase 13).
//
// Quand la couche Biodiversité est ACTIVE, toucher la carte ouvre la fiche
// d'un nouveau relevé à cet endroit : un marqueur provisoire, règne, espèce,
// date, observateur… Rien n'existe en base avant « Enregistrer » — le point et
// le relevé sont créés ensemble (`POST /map/observations`) ; fermer la fiche
// retire le marqueur provisoire, sans rien à supprimer. Sur un téléphone, le
// bouton « À ma position » fait la même chose là où l'on se tient (GPS haute
// précision, précision affichée).
//
// Chaque relevé est une pastille : une feuille verte pour la flore, une patte
// brune pour la faune, l'espèce en libellé à partir du zoom 18 (la règle
// commune des libellés de la carte).
//
// Ce module tient l'état du mode ; le contrôleur `map` lui prête sa carte, ses
// cibles et ses méthodes (`loadLayer`, `openPanel`, `discardPending`,
// `highlightSelection`, `showNotice`, `findFeatureLayer`, `focusFeature`).

import L from '~/utils/leaflet_global';
import { GPS_MAX_ACCURACY, isFreshFix } from '~/utils/map_placement';
import '~/stylesheets/map_biodiversity.css';

// MÊMES tracés et couleurs que `MapObservationsHelper` (la liste du panneau) :
// les changer des deux côtés à la fois.
export const OBSERVATION_GLYPHS = {
  flora:
    '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/>' +
    '<path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>',
  fauna:
    '<circle cx="11" cy="4" r="2"/><circle cx="18" cy="8" r="2"/><circle cx="20" cy="16" r="2"/>' +
    '<path d="M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z"/>',
};
export const OBSERVATION_COLORS = { flora: '#2E7D4F', fauna: '#8A6F47' };
const PENDING_COLOR = '#0B3D3A';
const GPS_COLOR = '#1F5F4A';
const GPS_WEAK_COLOR = '#C97B3D';
const GPS_WATCH_MS = 60000;

export function isObservationFeature(feature) {
  return feature?.properties?.feature_kind === 'observation';
}

// `realm` absent = le marqueur provisoire d'un relevé pas encore enregistré.
export function observationIcon(leaflet, realm, selected = false) {
  const size = selected ? 36 : 30;
  const glyph = OBSERVATION_GLYPHS[realm];
  const color = OBSERVATION_COLORS[realm] || PENDING_COLOR;
  const classes = ['map-observation-pin'];
  if (selected) classes.push('map-observation-pin--selected');
  if (!glyph) classes.push('map-observation-pin--pending');
  const inner = glyph
    ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph}</svg>`
    : '+';
  return leaflet.divIcon({
    className: 'map-observation-pin-wrapper',
    html: `<span class="${classes.join(' ')}" style="--observation-color: ${color}">${inner}</span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    // Le libellé (l'espèce) part du bord droit de la pastille.
    tooltipAnchor: [size / 2, 0],
  });
}

export function observationMarker(leaflet, feature, latlng) {
  const props = feature?.properties || {};
  return leaflet.marker(latlng, {
    icon: observationIcon(leaflet, props.realm),
    riseOnHover: true,
    zIndexOffset: 150,
    title: [props.species, props.observed_on].filter(Boolean).join(' — '),
  });
}

const GpsControl = L.Control.extend({
  options: { position: 'bottomright' },

  onAdd() {
    const container = L.DomUtil.create('div', 'map-observation-gps');
    container.dataset.observationGps = 'true';
    L.DomEvent.disableClickPropagation(container);
    L.DomEvent.disableScrollPropagation(container);
    this.status = L.DomUtil.create('p', 'map-observation-gps__status', container);
    this.status.setAttribute('role', 'status');
    const row = L.DomUtil.create('div', '', container);
    row.style.display = 'flex';
    row.style.gap = '0.375rem';
    this.cancel = L.DomUtil.create('button', 'map-observation-gps__cancel', row);
    this.cancel.type = 'button';
    this.cancel.textContent = 'Annuler';
    this.button = L.DomUtil.create('button', 'map-observation-gps__button', row);
    this.button.type = 'button';
    L.DomEvent.on(this.button, 'click', () => this.options.onPress());
    L.DomEvent.on(this.cancel, 'click', () => this.options.onCancel());
    this.options.onReady(this);
    return container;
  },
});

export class BiodiversityMode {
  constructor(controller) {
    this.c = controller;
    this.control = null;
    this.watchId = null;
    this.fix = null;
    this.fixCircle = null;
    this.forceArmed = false;
  }

  destroy() {
    this.stopGps();
    this.removeControl();
  }

  get active() {
    return this.c.activeLayerKind === 'biodiversity';
  }

  layerId() {
    return this.c.layerNameTargets.find((button) => button.dataset.layerKind === 'biodiversity')?.dataset.layerId;
  }

  newUrl() {
    return this.c.element.querySelector('[data-new-observation-url]')?.dataset.newObservationUrl;
  }

  onActivate(kind) {
    if (kind === 'biodiversity') {
      this.c.showNotice('Touchez la carte pour y noter une plante ou un animal.');
      this.addControl();
    } else {
      this.stopGps();
      this.removeControl();
    }
  }

  // En mode Biodiversité, un objet d'une autre couche (une zone, un chemin)
  // touché ne s'ouvre pas : le relevé se pose là où l'on a touché. Un relevé
  // existant, lui, s'ouvre.
  interceptFeatureClick(event, feature) {
    if (!this.active || isObservationFeature(feature)) return false;
    L.DomEvent.stopPropagation(event);
    this.onMapClick(event);
    return true;
  }

  onMapClick(event) {
    if (!this.active || this.c.placement?.active || !event?.latlng) return;
    const pm = this.c.map.pm;
    if (pm?.globalDrawModeEnabled?.() || pm?.globalEditModeEnabled?.() || pm?.globalRemovalModeEnabled?.()) return;
    this.openNew(event.latlng);
  }

  openNew(latlng) {
    const url = this.newUrl();
    if (!url) return;

    // Une couche masquée ne reçoit pas de relevé à l'aveugle : on la rallume.
    const toggle = this.c.layerToggleTargets.find((t) => t.dataset.layerId === this.layerId());
    if (toggle && !toggle.checked) {
      toggle.checked = true;
      toggle.dispatchEvent(new Event('change'));
    }

    this.c.discardPending();
    this.c.selectedFeatureId = null;
    this.c.highlightSelection();
    // `pendingLayer` : retiré par `discardPending` à la fermeture de la fiche
    // comme à l'enregistrement (la couche rechargée montre alors le vrai point).
    this.c.pendingLayer = L.marker(latlng, {
      icon: observationIcon(L, null, true),
      interactive: false,
      zIndexOffset: 1000,
    }).addTo(this.c.map);

    const { lat, lng } = latlng;
    this.c.openPanel(`${url}?lat=${lat.toFixed(7)}&lng=${lng.toFixed(7)}`);
  }

  // Une ligne de la liste : la carte se centre sur le relevé et ouvre sa fiche.
  // La couche est chargée si elle ne l'est pas encore (échec réseau passé).
  async focus(id) {
    if (!id) return;
    if (!this.c.findFeatureLayer(String(id))) {
      const layerId = this.layerId();
      if (layerId) await this.c.loadLayer(layerId);
    }
    this.c.focusFeatureValue = Number(id);
    this.c.focusFeature();
  }

  // Seules les pastilles dont l'état change sont redessinées.
  highlight(layer, selected) {
    if (!layer.setIcon || !isObservationFeature(layer.feature) || layer.observationSelected === selected) return;
    layer.observationSelected = selected;
    layer.setIcon(observationIcon(L, layer.feature.properties?.realm, selected));
    layer.setZIndexOffset(selected ? 1000 : 150);
  }

  // La liste du panneau suit chaque enregistrement et chaque suppression.
  onSaved(panel) {
    if (panel?.dataset.observationPanel) this.refreshList();
  }

  onDeleted(layerId) {
    if (String(layerId) === String(this.layerId())) this.refreshList();
  }

  refreshList() {
    const frame = this.c.element.querySelector('turbo-frame#map_observations');
    if (frame?.getAttribute('src')) frame.reload();
  }

  // ── « À ma position » (téléphone) ──────────────────────────────────────────

  addControl() {
    if (this.control || !this.c.map) return;
    this.control = new GpsControl({
      onReady: (control) => {
        this.controlUi = control;
        this.renderControl();
      },
      onPress: () => this.pressGps(),
      onCancel: () => this.stopGps(),
    }).addTo(this.c.map);
  }

  removeControl() {
    if (this.control) this.control.remove();
    this.control = null;
    this.controlUi = null;
  }

  pressGps() {
    if (this.watchId === null) this.startGps();
    else this.confirmGps();
  }

  startGps() {
    if (!navigator.geolocation) {
      this.c.showNotice("Ce navigateur ne donne pas la position : touchez la carte à l'endroit du relevé.");
      return;
    }
    this.stopGps();
    this.fix = null;
    this.forceArmed = false;
    this.gpsStartedAt = Date.now();
    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.onGpsFix(position),
      (error) => this.onGpsError(error),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 }
    );
    // Une recherche oubliée ne vide pas la batterie.
    this.watchTimer = setTimeout(() => this.stopGps(), GPS_WATCH_MS);
    this.renderControl();
  }

  onGpsFix(position) {
    // La position en cache de l'appui précédent n'est pas celle d'ici.
    if (!isFreshFix(position, this.gpsStartedAt)) return;
    const { latitude, longitude, accuracy } = position.coords;
    // On garde la meilleure position vue : une mesure plus floue ne la remplace pas.
    if (this.fix && accuracy > this.fix.accuracy) return;
    const first = !this.fix;
    this.fix = { lat: latitude, lng: longitude, accuracy };
    const color = accuracy <= GPS_MAX_ACCURACY ? GPS_COLOR : GPS_WEAK_COLOR;
    if (this.fixCircle) {
      this.fixCircle.setLatLng([latitude, longitude]).setRadius(accuracy).setStyle({ color });
    } else {
      this.fixCircle = L.circle([latitude, longitude], {
        radius: accuracy, color, weight: 1, fillOpacity: 0.12, interactive: false,
      }).addTo(this.c.map);
    }
    if (first) this.c.map.setView([latitude, longitude], Math.max(this.c.map.getZoom(), 19));
    this.renderControl();
  }

  onGpsError(error) {
    this.stopGps();
    this.c.showNotice(
      error?.code === 1
        ? 'La géolocalisation est refusée : touchez la carte à l’endroit du relevé.'
        : 'Position indisponible : touchez la carte à l’endroit du relevé.'
    );
  }

  // Une position floue demande une seconde pression : on ne pose pas un relevé
  // à 40 m près sans le savoir.
  confirmGps() {
    if (!this.fix) return;
    if (this.fix.accuracy > GPS_MAX_ACCURACY && !this.forceArmed) {
      this.forceArmed = true;
      this.renderControl();
      return;
    }
    const latlng = L.latLng(this.fix.lat, this.fix.lng);
    this.stopGps();
    this.openNew(latlng);
  }

  stopGps() {
    if (this.watchId !== null) navigator.geolocation?.clearWatch(this.watchId);
    this.watchId = null;
    clearTimeout(this.watchTimer);
    if (this.fixCircle) this.fixCircle.remove();
    this.fixCircle = null;
    this.fix = null;
    this.forceArmed = false;
    this.renderControl();
  }

  renderControl() {
    const ui = this.controlUi;
    if (!ui) return;
    const watching = this.watchId !== null;
    const accuracy = this.fix ? Math.round(this.fix.accuracy) : null;
    const precise = this.fix && this.fix.accuracy <= GPS_MAX_ACCURACY;

    ui.cancel.style.display = watching ? '' : 'none';
    ui.button.classList.toggle('map-observation-gps__button--weak', Boolean(this.fix && !precise));
    if (!watching) {
      ui.button.textContent = 'À ma position';
      ui.status.textContent = '';
    } else if (!this.fix) {
      ui.button.textContent = 'Recherche…';
      ui.status.textContent = 'Recherche de la position, restez à découvert.';
    } else if (precise) {
      ui.button.textContent = `Noter ici (± ${accuracy} m)`;
      ui.status.textContent = `Position à ± ${accuracy} m.`;
    } else if (this.forceArmed) {
      ui.button.textContent = `Noter quand même (± ${accuracy} m)`;
      ui.status.textContent = `Position encore floue (± ${accuracy} m) : touchez encore pour noter quand même, ou attendez.`;
    } else {
      ui.button.textContent = `Noter ici (± ${accuracy} m)`;
      ui.status.textContent = `Position encore floue (± ${accuracy} m) : attendez qu'elle s'affine.`;
    }
  }
}
