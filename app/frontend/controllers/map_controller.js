import { Controller } from '@hotwired/stimulus';
import L from '~/utils/leaflet_global';
import '@geoman-io/leaflet-geoman-free';
import 'leaflet/dist/leaflet.css';
import '@geoman-io/leaflet-geoman-free/dist/leaflet-geoman.css';
import '~/stylesheets/map.css';

// Style de la couche Gestion (phase 2) : polygones `forest` remplis à 25 %,
// accès en pointillés `bark`, points en marqueur rond. Couleurs du thème
// Tailwind (`tailwind.config.js`).
const FOREST = '#0B3D3A';
const BARK = '#8A6F47';
// Carte du jour (phase 3) : `ember` du thème pour l'occupé, `forest-tint` pour
// le libre, hachures des deux pour une arrivée ou un départ.
const EMBER = '#C97B3D';
const FOREST_TINT = '#E4EEEA';
const HATCH_ID = 'map-venue-hatch';
const VENUE_KINDS = ['lodging', 'space'];
const LABEL_MIN_ZOOM = 18;
const VISIBILITY_KEY = 'claudy.map.layers.visible';

// La carte du domaine (epic #348, phase 1).
//
// Tout ce que ce contrôleur sait de la carte arrive par des `data-*-value` :
// l'URL des tuiles, l'emprise, les zooms. Rien n'est en dur ici, parce que les
// fonds sont versionnés par date (décision 11) et qu'un second vol ne doit
// demander aucune ligne de JavaScript.
export default class extends Controller {
  static targets = [
    'canvas',
    'panel',
    'panelToggle',
    'panelBody',
    'panelChevron',
    'reliefToggle',
    'locateButton',
    'notice',
    'layerToggle',
    'layerName',
    'toolbar',
    'tool',
    'panelContainer',
    'featureFrame',
    'dateBar',
    'dateLabel',
    'dateHint',
    'dateInput',
    'todayButton',
    'venuesTodo',
  ];

  static values = {
    tilesUrl: String,
    layerKey: String,
    bounds: Array,
    center: Array,
    minZoom: { type: Number, default: 12 },
    maxZoom: { type: Number, default: 20 },
    hasRelief: { type: String, default: 'false' },
    featuresUrl: String,
    newFeatureUrl: String,
    occupancyUrl: String,
    venueUrl: String,
    date: String,
    today: String,
  };

  connect() {
    const bounds = this.boundsValue.length === 2 ? L.latLngBounds(this.boundsValue) : null;

    this.map = L.map(this.canvasTarget, {
      center: this.centerValue.length === 2 ? this.centerValue : [50.3414088, 4.9078535],
      zoom: 17,
      minZoom: this.minZoomValue,
      maxZoom: this.maxZoomValue,
      // `maxBounds` avec un peu de mou : coller l'emprise au pixel près rend le
      // déplacement élastique et désagréable au doigt.
      maxBounds: bounds ? bounds.pad(0.25) : undefined,
      zoomControl: false,
      attributionControl: false,
    });

    // En HAUT à droite : en bas, le contrôle se superposait au bouton « Ma
    // position », et deux cibles tactiles qui se recouvrent sur un téléphone,
    // c'est un clic sur deux qui rate.
    L.control.zoom({ position: 'topright' }).addTo(this.map);

    this.rgbLayer = this.tileLayer('rgb').addTo(this.map);
    this.demLayer = null;

    if (bounds) this.map.fitBounds(bounds);

    this.locating = false;
    this.locationMarker = null;
    this.locationCircle = null;

    this.map.on('locationfound', (event) => this.onLocationFound(event));
    this.map.on('locationerror', () => this.onLocationError());

    this.setupFeatures();

    // Leaflet mesure son conteneur au montage. Dans une page Turbo le conteneur
    // n'a pas toujours sa taille finale à ce moment-là : sans ce recalcul, la
    // carte s'affiche en tuiles grises sur un quart de l'écran.
    requestAnimationFrame(() => this.map.invalidateSize());
  }

  disconnect() {
    this.panelObserver?.disconnect();
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }

  tileLayer(kind) {
    return L.tileLayer(this.tilesUrlValue.replace('{kind}', kind), {
      minZoom: this.minZoomValue,
      maxZoom: this.maxZoomValue,
      // Hors de l'emprise il n'y a PAS de tuile, et c'est normal : le fond uni
      // du conteneur reste visible plutôt qu'une grille de carrés cassés.
      errorTileUrl:
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      bounds: this.boundsValue.length === 2 ? L.latLngBounds(this.boundsValue) : undefined,
      keepBuffer: 4,
    });
  }

  togglePanel() {
    const open = !this.panelBodyTarget.classList.toggle('hidden');
    this.panelToggleAria(open);
  }

  panelToggleAria(open) {
    if (this.hasPanelChevronTarget) {
      this.panelChevronTarget.classList.toggle('-rotate-90', !open);
    }
    if (this.hasPanelToggleTarget) {
      this.panelToggleTarget.setAttribute('aria-expanded', String(open));
    }
  }

  toggleRelief(event) {
    if (event.target.checked) {
      // Le relief se SUPERPOSE à l'ortho, il ne la remplace pas : à 60 %, on
      // lit encore ce qu'il y a au sol.
      this.demLayer = this.tileLayer('dem');
      this.demLayer.setOpacity(0.6);
      this.demLayer.addTo(this.map);
    } else if (this.demLayer) {
      this.map.removeLayer(this.demLayer);
      this.demLayer = null;
    }
  }

  toggleLocate() {
    this.locating = !this.locating;
    this.locateButtonTarget.setAttribute('aria-pressed', String(this.locating));
    this.locateButtonTarget.classList.toggle('text-4s-main', this.locating);

    if (this.locating) {
      // `watch: true` : sur le terrain, la position bouge — un point figé au
      // premier relevé est pire que pas de point du tout.
      this.map.locate({ watch: true, enableHighAccuracy: true, setView: true, maxZoom: 19 });
    } else {
      this.map.stopLocate();
      this.clearLocation();
    }
  }

  onLocationFound(event) {
    this.clearLocation();
    this.locationMarker = L.circleMarker(event.latlng, {
      radius: 7,
      color: '#ffffff',
      weight: 2,
      fillColor: '#024442',
      fillOpacity: 1,
      pmIgnore: true,
    }).addTo(this.map);
    this.locationCircle = L.circle(event.latlng, {
      radius: event.accuracy,
      color: '#024442',
      weight: 1,
      fillOpacity: 0.08,
      pmIgnore: true,
    }).addTo(this.map);
  }

  onLocationError() {
    this.locating = false;
    this.locateButtonTarget.setAttribute('aria-pressed', 'false');
    this.locateButtonTarget.classList.remove('text-4s-main');
    this.showNotice('Position indisponible — la géolocalisation est refusée ou hors de portée.');
  }

  clearLocation() {
    [this.locationMarker, this.locationCircle].forEach((layer) => {
      if (layer) this.map.removeLayer(layer);
    });
    this.locationMarker = null;
    this.locationCircle = null;
  }

  showNotice(message) {
    if (!this.hasNoticeTarget) return;

    this.noticeTarget.textContent = message;
    this.noticeTarget.classList.remove('hidden');
    clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => this.noticeTarget.classList.add('hidden'), 4000);
  }
  // ── Couches et objets (epic #348, phase 2) ────────────────────────────────
  //
  // Chaque couche typée est un `L.geoJSON` chargé depuis
  // `/map/features.json?layer_id=…`. La case du panneau l'affiche ou la masque
  // (état gardé en `localStorage`) ; le nom la rend ACTIVE, et si elle est de
  // kind `management`, la barre d'outils Geoman apparaît.

  async setupFeatures() {
    if (!this.hasFeaturesUrlValue || !this.featuresUrlValue) return;

    this.featureLayers = {};
    this.activeLayerId = null;
    this.selectedFeatureId = null;
    this.pendingLayer = null;
    this.pendingGeometry = null;

    this.geomanReady = Boolean(this.map?.pm);
    if (this.geomanReady) {
      // Pas de barre Geoman par défaut : la nôtre (44 px, au doigt) la remplace.
      this.map.pm.setGlobalOptions({ snappable: true, snapDistance: 15 });
      this.map.pm.setLang('fr');
      this.map.on('pm:create', (event) => this.onDrawCreate(event));
      this.map.on('pm:remove', (event) => this.onFeatureRemoved(event));
      this.map.on('pm:drawend', () => this.resetTools());
    }

    this.map.on('zoomend', () => this.updateLabels());
    this.updateLabels();
    this.observePanel();

    const visibility = this.readVisibility();
    // `allSettled` : une couche qui ne se charge pas (réseau de terrain, session
    // expirée) ne doit pas empêcher les autres ni la barre d'outils d'arriver.
    await Promise.allSettled(
      this.layerToggleTargets.map((toggle) => {
        const id = toggle.dataset.layerId;
        toggle.checked = visibility[id] !== false;
        return this.loadLayer(id);
      })
    );
    if (!this.map) return;

    // La carte du jour est la vue par défaut (phase 3) : la couche des lieux
    // est active en arrivant, la Gestion à défaut.
    const initial =
      this.layerNameTargets.find((b) => b.dataset.layerKind === 'venues') ||
      this.layerNameTargets.find((b) => b.dataset.layerKind === 'management');
    if (initial) this.setActiveLayer(initial.dataset.layerId, initial.dataset.layerKind);

    this.updateDateBar();
    await this.loadOccupancy();
  }

  async loadLayer(id) {
    const response = await fetch(`${this.featuresUrlValue}?layer_id=${encodeURIComponent(id)}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    if (!response.ok) return;
    const collection = await response.json();
    // La page a pu être quittée pendant le chargement.
    if (!this.map) return;

    if (this.featureLayers[id]) this.map.removeLayer(this.featureLayers[id]);

    const nameButton = this.layerNameTargets.find((b) => b.dataset.layerId === String(id));
    if (nameButton?.dataset.layerKind === 'venues') this.venuesLayerId = String(id);

    const group = L.geoJSON(collection, {
      style: (feature) => this.featureStyle(feature, false),
      pointToLayer: (feature, latlng) => L.circleMarker(latlng, this.featureStyle(feature, false)),
      onEachFeature: (feature, layer) => this.bindFeature(feature, layer, id),
    });
    this.featureLayers[id] = group;

    const toggle = this.layerToggleTargets.find((t) => t.dataset.layerId === String(id));
    if (!toggle || toggle.checked) group.addTo(this.map);
    this.ensureHatchPattern();
    this.updateLabels();
    return group;
  }

  bindFeature(feature, layer, layerId) {
    layer.featureId = feature.id;
    layer.layerId = layerId;
    const name = feature.properties?.name;
    if (name) {
      layer.bindTooltip(name, {
        permanent: true,
        direction: 'center',
        className: 'map-feature-label',
      });
    }
    layer.on('click', (event) => {
      // Pendant un tracé, le clic appartient à Geoman (il pose un sommet) : sans
      // cette sortie, poser un point DANS une zone ouvrait la fiche de la zone.
      if (
        this.map.pm?.globalRemovalModeEnabled?.() ||
        this.map.pm?.globalEditModeEnabled?.() ||
        this.map.pm?.globalDrawModeEnabled?.()
      ) {
        return;
      }
      L.DomEvent.stopPropagation(event);
      if (this.isVenue(feature)) this.selectVenue(feature.id);
      else this.selectFeature(feature.id);
    });
    // Sommets déplacés ou objet glissé : la géométrie est enregistrée tout de
    // suite, et le champ caché de la fiche ouverte suit.
    layer.on('pm:edit', () => this.saveGeometry(layer));
  }

  featureStyle(feature, selected) {
    const type = feature?.geometry?.type;
    const weight = selected ? 5 : 2;
    if (this.isVenue(feature)) return this.venueStyle(feature, selected);
    if (type === 'Polygon') {
      return { color: FOREST, weight, fillColor: FOREST, fillOpacity: 0.25 };
    }
    if (type === 'LineString') {
      return { color: BARK, weight: selected ? 6 : 4, dashArray: '8 8', lineCap: 'round' };
    }
    return {
      radius: selected ? 10 : 8,
      color: '#ffffff',
      weight: selected ? 4 : 2,
      fillColor: FOREST,
      fillOpacity: 1,
    };
  }

  // Les libellés n'apparaissent qu'à partir du zoom 18 : plus loin, ils
  // recouvrent la carte au lieu de l'expliquer.
  updateLabels() {
    const container = this.map.getContainer();
    container.classList.toggle('map-labels-hidden', this.map.getZoom() < LABEL_MIN_ZOOM);
  }

  toggleLayer(event) {
    const id = event.target.dataset.layerId;
    const group = this.featureLayers?.[id];
    if (group) {
      if (event.target.checked) group.addTo(this.map);
      else this.map.removeLayer(group);
    }
    const visibility = this.readVisibility();
    visibility[id] = event.target.checked;
    this.writeVisibility(visibility);
    if (id === this.venuesLayerId) this.updateDateBar();
  }

  activateLayer(event) {
    const button = event.currentTarget;
    this.setActiveLayer(button.dataset.layerId, button.dataset.layerKind);
  }

  setActiveLayer(id, kind) {
    this.activeLayerId = String(id);
    this.activeLayerKind = kind;
    this.layerNameTargets.forEach((button) => {
      const active = button.dataset.layerId === this.activeLayerId;
      button.classList.toggle('bg-teal-50', active);
      button.classList.toggle('font-medium', active);
      button.classList.toggle('text-4s-main', active);
      button.setAttribute('aria-current', active ? 'true' : 'false');
    });

    const editable = ['management', 'venues'].includes(kind) && this.geomanReady;
    // Les gîtes et salles se tracent en zones : point et ligne restent à la
    // Gestion.
    this.toolTargets.forEach((button) => {
      const kinds = button.dataset.toolKinds?.split(' ');
      button.classList.toggle('hidden', Boolean(kinds) && !kinds.includes(kind));
    });
    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle('hidden', !editable);
      this.toolbarTarget.classList.toggle('flex', editable);
    }
    if (!editable) this.disableTools();
  }

  useTool(event) {
    const tool = event.currentTarget.dataset.tool;
    if (!this.geomanReady || !this.activeLayerId) return;

    const wasActive = event.currentTarget.getAttribute('aria-pressed') === 'true';
    this.disableTools();
    if (wasActive) return;

    // Une couche masquée ne s'édite pas à l'aveugle : on la rallume.
    const toggle = this.layerToggleTargets.find((t) => t.dataset.layerId === this.activeLayerId);
    if (toggle && !toggle.checked) {
      toggle.checked = true;
      toggle.dispatchEvent(new Event('change'));
    }

    if (tool === 'edit') {
      this.map.pm.enableGlobalEditMode({ allowSelfIntersection: false });
    } else if (tool === 'remove') {
      this.map.pm.enableGlobalRemovalMode();
    } else {
      this.map.pm.enableDraw(tool, {
        // Un tracé à la fois : sinon l'outil Point restait armé, et le clic
        // suivant remplaçait l'objet dont on remplissait la fiche.
        continueDrawing: false,
        templineStyle: { color: FOREST },
        hintlineStyle: { color: FOREST, dashArray: [5, 5] },
        pathOptions: this.featureStyle({ geometry: { type: { Polygon: 'Polygon', Line: 'LineString' }[tool] || 'Point' } }, false),
      });
    }
    event.currentTarget.setAttribute('aria-pressed', 'true');
    event.currentTarget.classList.add('bg-forest-tint', 'text-forest');
  }

  disableTools() {
    if (this.geomanReady) {
      this.map.pm.disableDraw();
      if (this.map.pm.globalEditModeEnabled()) this.map.pm.disableGlobalEditMode();
      if (this.map.pm.globalRemovalModeEnabled()) this.map.pm.disableGlobalRemovalMode();
    }
    this.resetTools();
  }

  resetTools() {
    this.toolTargets.forEach((button) => {
      const mode = button.dataset.tool;
      const stillOn =
        (mode === 'edit' && this.map.pm?.globalEditModeEnabled?.()) ||
        (mode === 'remove' && this.map.pm?.globalRemovalModeEnabled?.());
      if (stillOn) return;
      button.setAttribute('aria-pressed', 'false');
      button.classList.remove('bg-forest-tint', 'text-forest');
    });
  }

  // Une géométrie finie : rien n'est encore enregistré. La fiche s'ouvre avec
  // la géométrie dans son champ caché ; « Enregistrer » crée l'objet.
  onDrawCreate(event) {
    this.discardPending();
    this.pendingLayer = event.layer;
    this.pendingGeometry = event.layer.toGeoJSON().geometry;
    // Un sommet corrigé AVANT « Enregistrer » doit partir avec la fiche.
    event.layer.on('pm:edit', () => {
      this.pendingGeometry = event.layer.toGeoJSON().geometry;
      const field = this.geometryField();
      if (field) field.value = JSON.stringify(this.pendingGeometry);
    });
    const kind = { Point: 'point', LineString: 'path', Polygon: 'zone' }[this.pendingGeometry.type] || 'point';
    this.selectedFeatureId = null;
    this.openPanel(
      `${this.newFeatureUrlValue}?layer_id=${encodeURIComponent(this.activeLayerId)}&feature_kind=${kind}`
    );
  }

  async onFeatureRemoved(event) {
    const id = event.layer?.featureId;
    if (!id) return;
    // Geoman retire l'objet de la carte, pas de son groupe `L.geoJSON` : sans
    // ceci, décocher puis recocher la couche le faisait réapparaître.
    const layerId = event.layer.layerId;
    this.featureLayers?.[layerId]?.removeLayer(event.layer);
    const response = await this.request(`${this.featureUrl(id)}.json`, 'DELETE');
    if (!response.ok) this.loadLayer(layerId);
    if (String(this.selectedFeatureId) === String(id)) this.closePanel();
    if (event.layer?.layerId === this.venuesLayerId && this.hasVenuesTodoTarget) this.venuesTodoTarget.reload();
  }

  // Les PATCH d'un même objet partent l'un après l'autre : deux déplacements
  // rapprochés ne doivent jamais être enregistrés dans le désordre.
  saveGeometry(layer) {
    if (!layer.featureId) return Promise.resolve();
    const geometry = JSON.stringify(layer.toGeoJSON().geometry);
    this.geometryQueue ||= {};
    const previous = this.geometryQueue[layer.featureId] || Promise.resolve();
    const next = previous
      .catch(() => {})
      .then(() => this.request(`${this.featureUrl(layer.featureId)}.json`, 'PATCH', { map_feature: { geometry } }));
    this.geometryQueue[layer.featureId] = next;
    return next;
  }

  selectFeature(id) {
    this.discardPending();
    this.selectedFeatureId = id;
    this.highlightSelection();
    this.openPanel(this.featureUrl(id));
  }

  highlightSelection() {
    Object.values(this.featureLayers || {}).forEach((group) => {
      group.eachLayer((layer) => {
        const selected = String(layer.featureId) === String(this.selectedFeatureId);
        if (layer.setStyle) layer.setStyle(this.featureStyle(layer.feature, selected));
        if (layer.setRadius && layer.feature?.geometry?.type === 'Point') {
          layer.setRadius(selected ? 10 : 8);
        }
      });
    });
  }

  openPanel(url) {
    if (!this.hasFeatureFrameTarget) return;
    this.featureFrameTarget.src = url;
  }

  closePanel() {
    this.discardPending();
    this.selectedFeatureId = null;
    this.highlightSelection();
    if (this.hasFeatureFrameTarget) {
      this.featureFrameTarget.removeAttribute('src');
      this.featureFrameTarget.innerHTML = '';
    }
  }

  discardPending() {
    if (this.pendingLayer) this.map.removeLayer(this.pendingLayer);
    this.pendingLayer = null;
    this.pendingGeometry = null;
  }

  // La fiche vit dans une Turbo Frame que le serveur remplit (clic, création)
  // ou remplace (Turbo Stream à l'enregistrement). On l'observe pour : la
  // montrer ou la cacher selon qu'elle a du contenu, poser la géométrie d'un
  // objet neuf, et recharger la couche quand un enregistrement a réussi.
  observePanel() {
    if (!this.hasFeatureFrameTarget) return;
    this.panelObserver = new MutationObserver(() => this.onPanelChange());
    this.panelObserver.observe(this.featureFrameTarget, { childList: true });
    this.onPanelChange();
  }

  onPanelChange() {
    // Objet supprimé depuis sa fiche : on le retire de la carte, où il restait
    // dessiné (et renvoyait une 404 au clic suivant).
    const deleted = this.featureFrameTarget.querySelector('[data-feature-deleted]');
    if (deleted) {
      const layerId = deleted.dataset.layerId;
      deleted.remove();
      this.closePanel();
      if (layerId) this.loadLayer(layerId);
      return;
    }

    const panel = this.featureFrameTarget.querySelector('[data-feature-panel]');
    if (this.hasPanelContainerTarget) this.panelContainerTarget.classList.toggle('hidden', !panel);
    if (!panel) return;

    const field = this.geometryField();
    if (field && !field.value && this.pendingGeometry) field.value = JSON.stringify(this.pendingGeometry);

    if (panel.dataset.featureSaved === 'true' && panel.dataset.featureId) {
      // Enregistré : l'objet vit désormais dans la couche rechargée, le tracé
      // provisoire n'a plus de raison d'être.
      const id = panel.dataset.featureId;
      delete panel.dataset.featureSaved;
      this.discardPending();
      this.selectedFeatureId = id;
      // La couche de l'objet enregistré, pas forcément la couche active ; si
      // c'est celle des lieux, l'occupation et la liste « À tracer » suivent.
      const layerId = panel.dataset.layerId || this.activeLayerId;
      this.loadLayer(layerId).then(async () => {
        if (String(layerId) === this.venuesLayerId) {
          await this.loadOccupancy();
          if (this.hasVenuesTodoTarget) this.venuesTodoTarget.reload();
        }
        this.highlightSelection();
      });
    }
  }

  geometryField() {
    return this.hasFeatureFrameTarget
      ? this.featureFrameTarget.querySelector("[data-role='feature-geometry']")
      : null;
  }

  featureUrl(id) {
    return `${this.featuresUrlValue.replace(/\.json$/, '')}/${id}`;
  }

  async request(url, method, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    const response = await fetch(url, {
      method,
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': token || '',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!response.ok) this.showNotice("L'enregistrement a échoué — rechargez la page.");
    return response;
  }

  // ── Carte du jour (epic #348, phase 3) ────────────────────────────────────
  //
  // Les gîtes et salles tracés (couche `venues`) sont colorés selon leur
  // occupation au jour affiché, lue sur `/map/occupancy.json?date=…`. Le jour
  // vit dans l'URL (`?date=`) : un rechargement ou un lien partagé retombent
  // sur le même jour.

  isVenue(feature) {
    return VENUE_KINDS.includes(feature?.properties?.feature_kind);
  }

  venueStyle(feature, selected) {
    const state = this.occupancy?.[feature.id]?.state;
    const weight = selected ? 5 : 2;
    if (state === 'occupied') {
      return { color: EMBER, weight, fillColor: EMBER, fillOpacity: 0.55 };
    }
    if (state === 'turnover') {
      return { color: EMBER, weight, fillColor: `url(#${HATCH_ID})`, fillOpacity: 0.9 };
    }
    // Libre, ou pas encore relié à un gîte : le vert pâle du thème.
    return { color: FOREST, weight, fillColor: FOREST_TINT, fillOpacity: 0.6, dashArray: state ? null : '6 4' };
  }

  // Leaflet dessine les objets dans UN svg : on y pose une fois le motif de
  // hachures qu'une arrivée ou un départ utilise comme remplissage.
  ensureHatchPattern() {
    const svg = this.map.getPanes().overlayPane.querySelector('svg');
    if (!svg || svg.querySelector(`#${HATCH_ID}`)) return;

    const ns = 'http://www.w3.org/2000/svg';
    let defs = svg.querySelector('defs');
    if (!defs) {
      defs = document.createElementNS(ns, 'defs');
      svg.insertBefore(defs, svg.firstChild);
    }
    const pattern = document.createElementNS(ns, 'pattern');
    pattern.setAttribute('id', HATCH_ID);
    pattern.setAttribute('patternUnits', 'userSpaceOnUse');
    pattern.setAttribute('width', '10');
    pattern.setAttribute('height', '10');
    pattern.setAttribute('patternTransform', 'rotate(45)');
    const background = document.createElementNS(ns, 'rect');
    background.setAttribute('width', '10');
    background.setAttribute('height', '10');
    background.setAttribute('fill', FOREST_TINT);
    const stripe = document.createElementNS(ns, 'rect');
    stripe.setAttribute('width', '5');
    stripe.setAttribute('height', '10');
    stripe.setAttribute('fill', EMBER);
    pattern.append(background, stripe);
    defs.appendChild(pattern);
  }

  async loadOccupancy() {
    if (!this.hasOccupancyUrlValue || !this.occupancyUrlValue) return;

    const date = this.dateValue;
    const response = await fetch(`${this.occupancyUrlValue}?date=${encodeURIComponent(date)}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    });
    // Un clic rapide sur « jour suivant » : seule la réponse du dernier jour
    // demandé a le droit de colorer la carte.
    if (!response.ok || date !== this.dateValue) return;
    const payload = await response.json();
    this.occupancy = payload.states || {};
    this.highlightSelection();
  }

  selectVenue(id) {
    this.discardPending();
    this.selectedFeatureId = id;
    this.highlightSelection();
    this.openPanel(this.venueUrl(id));
  }

  venueUrl(id) {
    return `${this.venueUrlValue.replace('__ID__', encodeURIComponent(id))}?date=${encodeURIComponent(this.dateValue)}`;
  }

  previousDay() {
    this.shiftDate(-1);
  }

  nextDay() {
    this.shiftDate(1);
  }

  goToday() {
    this.setDate(this.todayValue);
  }

  pickDate(event) {
    if (event.target.value) this.setDate(event.target.value);
  }

  shiftDate(days) {
    const date = this.parseDate(this.dateValue);
    date.setUTCDate(date.getUTCDate() + days);
    this.setDate(date.toISOString().slice(0, 10));
  }

  setDate(iso) {
    if (!iso || iso === this.dateValue) return;
    this.dateValue = iso;

    const url = new URL(window.location.href);
    if (iso === this.todayValue) url.searchParams.delete('date');
    else url.searchParams.set('date', iso);
    window.history.replaceState(window.history.state, '', url);

    this.updateDateBar();
    this.loadOccupancy();

    // Le panneau d'un gîte ouvert suit le jour affiché.
    const panel = this.hasFeatureFrameTarget && this.featureFrameTarget.querySelector('[data-venue-panel]');
    if (panel && this.selectedFeatureId) this.openPanel(this.venueUrl(this.selectedFeatureId));
  }

  updateDateBar() {
    if (!this.hasDateBarTarget) return;

    const toggle = this.layerToggleTargets.find((t) => t.dataset.layerId === this.venuesLayerId);
    const visible = Boolean(this.venuesLayerId) && (!toggle || toggle.checked);
    this.dateBarTarget.classList.toggle('hidden', !visible);
    this.dateBarTarget.classList.toggle('flex', visible);

    const date = this.parseDate(this.dateValue);
    if (this.hasDateLabelTarget) {
      const label = date.toLocaleDateString('fr-BE', {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        timeZone: 'UTC',
      });
      // « Samedi 26 septembre » : majuscule au jour seulement, comme le serveur.
      this.dateLabelTarget.textContent = label.charAt(0).toUpperCase() + label.slice(1);
    }
    if (this.hasDateInputTarget) this.dateInputTarget.value = this.dateValue;

    const offset = Math.round((date - this.parseDate(this.todayValue)) / 86400000);
    if (this.hasDateHintTarget) this.dateHintTarget.textContent = this.relativeDay(offset);
    if (this.hasTodayButtonTarget) this.todayButtonTarget.classList.toggle('hidden', offset === 0);
  }

  relativeDay(offset) {
    if (offset === 0) return "aujourd'hui";
    if (offset === 1) return 'demain';
    if (offset === -1) return 'hier';
    return offset > 0 ? `dans ${offset} jours` : `il y a ${-offset} jours`;
  }

  // Les dates sont des jours, pas des instants : tout se calcule en UTC pour
  // qu'un changement d'heure ne fasse jamais sauter ou doubler un jour.
  parseDate(iso) {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(Date.UTC(year, month - 1, day));
  }

  readVisibility() {
    try {
      return JSON.parse(window.localStorage.getItem(VISIBILITY_KEY) || '{}');
    } catch {
      return {};
    }
  }

  writeVisibility(visibility) {
    try {
      window.localStorage.setItem(VISIBILITY_KEY, JSON.stringify(visibility));
    } catch {
      // Navigation privée ou stockage plein : l'état ne survit pas, rien de grave.
    }
  }
}
