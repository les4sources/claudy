import { Controller } from '@hotwired/stimulus';
import L from '~/utils/leaflet_global';
import '@geoman-io/leaflet-geoman-free';
import 'leaflet/dist/leaflet.css';
import '@geoman-io/leaflet-geoman-free/dist/leaflet-geoman.css';
import '~/stylesheets/map.css';
import { welcomeIcon, welcomeMarker, welcomeProperties, welcomeStyle } from '~/utils/map_welcome';
import { isPlantFeature, plantIcon, plantMarker } from '~/utils/map_plants';
import { PlantPlacement } from '~/utils/map_placement';
import {
  NETWORK_LABEL_MIN_ZOOM,
  handleNodeTypeChange,
  isNetworkFeature,
  networkNodeIcon,
  networkNodeMarker,
  networkStyle,
} from '~/utils/map_networks';
import { UnifiStatusPoller, handleUnifiEquipmentChange } from '~/utils/map_unifi';
import { CommentMode, commentMarker, isCommentFeature } from '~/utils/map_comments';
import { SketchMode } from '~/utils/map_sketches';
import { BiodiversityMode, isObservationFeature, observationMarker } from '~/utils/map_biodiversity';
import { MapSearch } from '~/utils/map_search';
import { syncPointLabel } from '~/utils/map_labels';
import { MeasureTool } from '~/utils/map_measure';
import { GeoportailInfo } from '~/utils/map_geoportail';

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
// Au-delà du zoom le plus fin des tuiles (`max_zoom` du fond, 20 pour
// l'ortho 2023), Leaflet agrandit les dernières tuiles : deux crans de plus
// pour poser un point au pied d'un arbre ou d'une prise.
const OVERZOOM = 2;
// Plantes (phase 7) : le pictogramme de strate apparaît un cran avant les noms.
const PLANT_GLYPH_MIN_ZOOM = 17;
// Une seule couche à la fois (Michael, 2026-09-28 : plusieurs couches
// superposées, « on s'y perd ») : on retient la dernière choisie.
const ACTIVE_LAYER_KEY = 'claudy.map.layer.active';
// Valeur retenue quand on a choisi « Aucune » couche.
const NO_LAYER = 'none';

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
    'panelActive',
    'modeBar',
    'reliefToggle',
    'locateButton',
    'notice',
    'layerToggle',
    'layerName',
    'layerNone',
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
    'welcomeLegend',
    // Phase 7 : le mode Placement des plantes (tiroir, bandeau, compteurs).
    'placementDrawer',
    'unplacedFrame',
    'unplacedCount',
    'placementBanner',
    'placementMessage',
    'placementHint',
    'placementGps',
    'placementGpsConfirm',
    'placementLast',
    'placementLastMessage',
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
    // Phase 6 : l'objet à montrer en arrivant (`/map?feature=<id>`, lien du
    // carnet) et les objets porteurs d'une tâche du mois (vue « ce mois-ci »).
    focusFeature: Number,
    currentTasksUrl: String,
    // Phase 7 : la fiche d'une plante (`/map/plants/__ID__`), ouverte au clic
    // sur son point à la place de la fiche générique de l'objet.
    plantUrl: String,
    // Le mode Placement : la liste des plantes à placer, la pose (et le
    // déplacement) d'un point, son annulation. `/map?plant=<id>` ouvre la fiche
    // d'une plante, placée ou non.
    unplacedUrl: String,
    placeUrl: String,
    unplaceUrl: String,
    focusPlant: Number,
    // « Nouvelle plante » : la fiche vide, ouverte d'office par
    // `/map?plant=new` (lien de la liste des plantes).
    newPlantUrl: String,
    openNewPlant: Boolean,
    // Phase 10 : le statut UniFi des nœuds Ethernet (`utils/map_unifi.js`).
    unifiDevicesUrl: String,
  };

  connect() {
    const bounds = this.boundsValue.length === 2 ? L.latLngBounds(this.boundsValue) : null;

    this.map = L.map(this.canvasTarget, {
      center: this.centerValue.length === 2 ? this.centerValue : [50.3414088, 4.9078535],
      zoom: 17,
      minZoom: this.minZoomValue,
      maxZoom: this.maxZoomValue + OVERZOOM,
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

    this.placement = new PlantPlacement(this);
    this.unifi = new UnifiStatusPoller(this, this.unifiDevicesUrlValue, (feature, selected) =>
      networkNodeIcon(L, feature, selected)
    );
    this.element.addEventListener('change', handleUnifiEquipmentChange);
    this.element.addEventListener('change', handleNodeTypeChange);
    // Phase 11 : le mode Commentaires (utils/map_comments.js).
    this.comments = new CommentMode(this);
    // Phase 12 : les notes manuscrites (utils/map_sketches.js).
    this.sketches = new SketchMode(this);
    // Phase 13 : le mode Biodiversité (utils/map_biodiversity.js).
    this.biodiversity = new BiodiversityMode(this);
    // Phase 14 : la recherche du mode actif (utils/map_search.js).
    this.search = new MapSearch(this);
    // Phase 14 : l'outil Mesure, dans tous les modes (utils/map_measure.js).
    this.measure = new MeasureTool(this, L);
    // L'information au clic des couches du Géoportail (utils/map_geoportail.js).
    this.geoportailInfo = new GeoportailInfo(this, L);
    this.setupFeatures();

    // Sur un téléphone, le panneau des couches ouvert couvrait les deux tiers
    // de la carte : il démarre replié, la couche active lisible dans son titre.
    if (this.narrow) this.setPanelOpen(false);

    // Leaflet mesure son conteneur au montage. Dans une page Turbo le conteneur
    // n'a pas toujours sa taille finale à ce moment-là : sans ce recalcul, la
    // carte s'affiche en tuiles grises sur un quart de l'écran.
    requestAnimationFrame(() => this.map.invalidateSize());
  }

  disconnect() {
    this.panelObserver?.disconnect();
    this.placement?.destroy();
    this.unifi?.stop();
    this.element.removeEventListener('change', handleUnifiEquipmentChange);
    this.element.removeEventListener('change', handleNodeTypeChange);
    this.comments?.destroy();
    this.sketches?.destroy();
    this.search?.destroy();
    this.measure?.destroy();
    this.biodiversity?.destroy();
    this.geoportailInfo?.destroy();
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }

  tileLayer(kind) {
    return L.tileLayer(this.tilesUrlValue.replace('{kind}', kind), {
      minZoom: this.minZoomValue,
      maxNativeZoom: this.maxZoomValue,
      maxZoom: this.maxZoomValue + OVERZOOM,
      // Hors de l'emprise il n'y a PAS de tuile, et c'est normal : le fond uni
      // du conteneur reste visible plutôt qu'une grille de carrés cassés.
      errorTileUrl:
        'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      bounds: this.boundsValue.length === 2 ? L.latLngBounds(this.boundsValue) : undefined,
      keepBuffer: 4,
    });
  }

  get narrow() {
    return !window.matchMedia('(min-width: 768px)').matches;
  }

  get panelOpen() {
    return this.hasPanelBodyTarget && !this.panelBodyTarget.classList.contains('hidden');
  }

  togglePanel() {
    this.setPanelOpen(!this.panelOpen);
  }

  setPanelOpen(open) {
    if (!this.hasPanelBodyTarget) return;
    this.panelBodyTarget.classList.toggle('hidden', !open);
    this.panelToggleAria(open);
  }

  // Sur un téléphone, le panneau se replie dès qu'on a choisi : c'est la carte
  // qu'on vient toucher.
  collapsePanelOnPhone() {
    if (this.narrow && this.panelOpen) this.setPanelOpen(false);
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
      // Au-dessus de l'ortho du Géoportail (z-index 2), sous ses autres couches.
      this.demLayer.setZIndex(3);
      this.demLayer.addTo(this.map);
    } else if (this.demLayer) {
      this.map.removeLayer(this.demLayer);
      this.demLayer = null;
    }
  }

  // Une couche WMS du Géoportail de Wallonie (MapGeoportailLayer) : tout ce
  // qu'il faut pour la construire est dans les `data-geoportail-*` de la case.
  // Le SPW dessine chaque tuile à la demande, à n'importe quel zoom, sauf les
  // couches qu'il masque sous une échelle : celles-là portent un zoom plafond,
  // au-delà duquel Leaflet agrandit la dernière tuile dessinée.
  toggleGeoportail(event) {
    const input = event.target;
    const { geoportailKey: key, geoportailMaxNativeZoom: maxNativeZoom } = input.dataset;
    this.geoportailLayers ||= {};

    if (input.checked) {
      this.geoportailLayers[key] = L.tileLayer
        .wms(input.dataset.geoportailUrl, {
          layers: input.dataset.geoportailLayers,
          styles: '',
          format: 'image/png',
          transparent: true,
          version: '1.3.0',
          opacity: Number(input.dataset.geoportailOpacity),
          zIndex: Number(input.dataset.geoportailZIndex),
          minZoom: this.minZoomValue,
          maxZoom: this.maxZoomValue + OVERZOOM,
          maxNativeZoom: maxNativeZoom ? Number(maxNativeZoom) : undefined,
          keepBuffer: 4,
        })
        .addTo(this.map);
    } else if (this.geoportailLayers[key]) {
      this.map.removeLayer(this.geoportailLayers[key]);
      delete this.geoportailLayers[key];
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
  // `/map/features.json?layer_id=…`. UNE SEULE couche est affichée à la fois :
  // la choisir dans le panneau l'affiche, masque les autres et la rend ACTIVE
  // (la barre d'outils suit son kind). La dernière choisie est retenue en
  // `localStorage`. Les cases `layerToggle`, invisibles, portent l'état affiché.

  async setupFeatures() {
    if (!this.hasFeaturesUrlValue || !this.featuresUrlValue) return;

    this.featureLayers = {};
    this.layerKinds = {};
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
    this.map.on('click', (event) => this.onMapClick(event));
    this.updateLabels();
    this.observePanel();

    // La couche choisie la dernière fois ; sinon la carte du jour (phase 3),
    // vue par défaut, et la Gestion à défaut.
    // « Aucune » choisie la dernière fois : la carte s'ouvre sans couche.
    const remembered = this.readActiveLayer();
    const initial =
      remembered === NO_LAYER
        ? null
        : this.layerNameTargets.find((b) => b.dataset.layerId === remembered) ||
          this.layerNameTargets.find((b) => b.dataset.layerKind === 'venues') ||
          this.layerNameTargets.find((b) => b.dataset.layerKind === 'management');
    this.layerToggleTargets.forEach((toggle) => {
      toggle.checked = Boolean(initial) && toggle.dataset.layerId === initial.dataset.layerId;
    });
    // `allSettled` : une couche qui ne se charge pas (réseau de terrain, session
    // expirée) ne doit pas empêcher les autres ni la barre d'outils d'arriver.
    await Promise.allSettled(this.layerToggleTargets.map((toggle) => this.loadLayer(toggle.dataset.layerId)));
    if (!this.map) return;

    if (initial) this.setActiveLayer(initial.dataset.layerId, initial.dataset.layerKind);
    else if (remembered === NO_LAYER) this.setActiveLayer(null, null);

    this.updateDateBar();
    await this.loadOccupancy();
    if (!this.map) return;
    // Après la couche active par défaut : l'objet demandé par l'URL l'emporte.
    this.focusFeature();
    if (this.focusPlantValue && this.hasPlantUrlValue) this.openPanel(this.plantUrl(this.focusPlantValue));
    if (this.openNewPlantValue) this.newPlant();
  }

  onMapClick(event) {
    // Sur un téléphone, toucher la carte panneau ouvert le replie, et rien
    // d'autre : on voulait retrouver la carte, pas y poser un commentaire.
    if (this.narrow && this.panelOpen) {
      this.setPanelOpen(false);
      return;
    }
    // Pendant une mesure (phase 14), le clic pose un sommet : aucun mode ne le prend.
    if (this.measure?.active) return;
    // En mode Placement, toucher la carte pose la plante choisie.
    this.placement?.onMapClick(event);
    // En mode Commentaires, toucher la carte ouvre un nouveau commentaire.
    this.comments?.onMapClick(event);
    // En mode Biodiversité, toucher la carte ouvre un nouveau relevé.
    this.biodiversity?.onMapClick(event);
    // Hors de tout mode et de tout tracé, une couche du Géoportail affichée
    // répond au clic : ce qu'elle sait de l'endroit touché, dans une bulle.
    const busy =
      this.placement?.active ||
      this.comments?.active ||
      this.biodiversity?.active ||
      this.sketches?.activeId ||
      this.map.pm?.globalDrawModeEnabled?.() ||
      this.map.pm?.globalEditModeEnabled?.() ||
      this.map.pm?.globalRemovalModeEnabled?.();
    if (!busy) this.geoportailInfo?.onMapClick(event);
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
    if (nameButton) this.layerKinds[String(id)] = nameButton.dataset.layerKind;
    if (nameButton?.dataset.layerKind === 'venues') this.venuesLayerId = String(id);

    const group = L.geoJSON(collection, {
      style: (feature) => this.featureStyle(feature, false),
      // Un point d'accueil porte son icône (phase 4) ; les autres restent des
      // pastilles rondes.
      pointToLayer: (feature, latlng) => {
        if (isPlantFeature(feature)) return plantMarker(L, feature, latlng);
        if (isNetworkFeature(feature)) return networkNodeMarker(L, feature, latlng);
        if (isCommentFeature(feature)) return commentMarker(L, feature, latlng);
        if (isObservationFeature(feature)) return observationMarker(L, feature, latlng);
        if (this.isWelcome(feature)) return welcomeMarker(L, feature, latlng);
        return L.circleMarker(latlng, this.featureStyle(feature, false));
      },
      onEachFeature: (feature, layer) => this.bindFeature(feature, layer, id),
    });
    this.featureLayers[id] = group;

    const toggle = this.layerToggleTargets.find((t) => t.dataset.layerId === String(id));
    if (!toggle || toggle.checked) group.addTo(this.map);
    this.ensureHatchPattern();
    this.updateLabels();
    // Une couche rechargée (enregistrement, suppression) recrée ses tracés : la
    // vue « ce mois-ci » doit les reprendre.
    this.applyMonthFocus();
    // Phase 10 : la couche Ethernet rechargée reprend ses pastilles UniFi.
    this.unifi?.sync();
    return group;
  }

  bindFeature(feature, layer, layerId) {
    layer.featureId = feature.id;
    layer.layerId = layerId;
    const name = feature.properties?.name;
    if (name) {
      // Le nom d'une plante se pose à droite de sa pastille, pas dessus.
      const plant = isPlantFeature(feature);
      // Un relevé (phase 13) et un nœud de réseau (phase 9) aussi ; le nom d'un
      // objet de réseau n'apparaît qu'au zoom 19.
      const observation = isObservationFeature(feature);
      const node = isNetworkFeature(feature) && feature.geometry?.type === 'Point';
      const network = isNetworkFeature(feature) ? ' map-network-label' : '';
      const aside = plant || observation || node;
      // Un point ne montre son nom qu'au survol ou au toucher (et tant qu'il
      // est sélectionné ou trouvé par la recherche) : serrés, leurs libellés
      // permanents se recouvraient. Zones et tracés gardent le leur.
      const point = feature.geometry?.type === 'Point';
      layer.bindTooltip(name, {
        permanent: !point,
        direction: aside ? 'right' : 'center',
        offset: aside ? [4, 0] : [0, 0],
        className:
          (plant ? 'map-feature-label map-plant-label' : observation ? 'map-feature-label map-observation-label' : 'map-feature-label') +
          network +
          (point ? ' map-hover-label' : ''),
      });
      // Leaflet referme le libellé en quittant le point : on le rouvre s'il
      // est épinglé.
      if (point) layer.on('mouseout', () => syncPointLabel(layer));
    }
    layer.on('click', (event) => {
      // L'outil Mesure (phase 14) prend le clic avant tout mode.
      if (this.measure?.interceptFeatureClick(event)) return;
      // En mode Placement, un objet touché (une zone, un autre arbre) ne
      // s'ouvre pas : la plante choisie se pose là où l'on a touché.
      if (this.placement?.active) {
        L.DomEvent.stopPropagation(event);
        this.placement.onMapClick(event);
        return;
      }
      // En mode Commentaires, on commente l'endroit touché, même dans une zone.
      if (this.comments?.interceptFeatureClick(event, feature)) return;
      // En mode Biodiversité, de même : le relevé se pose là où l'on touche.
      if (this.biodiversity?.interceptFeatureClick(event, feature)) return;
      // Pendant un tracé, le clic appartient à Geoman (il pose un sommet) : sans
      // cette sortie, poser un point DANS une zone ouvrait la fiche de la zone.
      if (this.map.pm?.globalDrawModeEnabled?.()) {
        // Un marqueur (nœud de réseau, plante…) ne remonte pas son clic à la
        // carte, où Geoman l'attend : on le lui passe, au centre du marqueur.
        // Un tracé commence et finit ainsi SUR un nœud, pas à côté.
        if (layer.options?.bubblingMouseEvents === false) {
          this.map.fire('click', { ...event, latlng: layer.getLatLng?.() || event.latlng });
        }
        return;
      }
      if (this.map.pm?.globalRemovalModeEnabled?.() || this.map.pm?.globalEditModeEnabled?.()) return;
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
    if (this.isWelcome(feature)) return welcomeStyle(feature, selected);
    // Réseaux (phase 9) : la couleur vient du JSON, ou de la couche active
    // pour ce qu'on dessine.
    const networkColor = feature?.properties?.color || this.layerNetworkColor(feature?.properties?.layer_id);
    if (networkColor) return networkStyle(feature, networkColor, selected);
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
    container.classList.toggle('map-plant-glyphs-hidden', this.map.getZoom() < PLANT_GLYPH_MIN_ZOOM);
    container.classList.toggle('map-network-labels-hidden', this.map.getZoom() < NETWORK_LABEL_MIN_ZOOM);
  }

  // Réseaux (phase 9) : la couleur d'une couche réseau, lue sur son bouton du
  // panneau (`data-network-color`) ; rien pour une autre couche.
  layerNetworkColor(layerId) {
    if (layerId == null) return null;
    return this.layerNameTargets.find((b) => b.dataset.layerId === String(layerId))?.dataset.networkColor || null;
  }

  // Une case cochée par le code (placement, lien `?feature=`, outil qui
  // rallume sa couche) : c'est choisir cette couche, donc masquer les autres.
  toggleLayer(event) {
    const id = event.target.dataset.layerId;
    if (event.target.checked) {
      const button = this.layerNameTargets.find((b) => b.dataset.layerId === String(id));
      this.setActiveLayer(id, button?.dataset.layerKind || this.layerKinds?.[id]);
    } else {
      this.showOnlyLayer(this.activeLayerId);
    }
  }

  // N'afficher que `id` : les autres groupes quittent la carte, leurs cases
  // sont décochées.
  showOnlyLayer(id) {
    this.layerToggleTargets.forEach((toggle) => {
      const visible = toggle.dataset.layerId === String(id);
      toggle.checked = visible;
      const group = this.featureLayers?.[toggle.dataset.layerId];
      if (!group || !this.map) return;
      if (visible) group.addTo(this.map);
      else this.map.removeLayer(group);
    });
    // Les éléments SVG d'une couche rallumée sont neufs : sans leurs classes.
    this.applyMonthFocus();
    // Phase 10 : masquer la couche Ethernet arrête la relecture des statuts.
    this.unifi?.sync();
    this.updateDateBar();
  }

  activateLayer(event) {
    const button = event.currentTarget;
    this.setActiveLayer(button.dataset.layerId, button.dataset.layerKind);
    this.collapsePanelOnPhone();
  }

  // « Aucune » : la carte sans aucune couche d'objets.
  clearActiveLayer() {
    this.setActiveLayer(null, null);
    this.collapsePanelOnPhone();
  }

  // `id` nul : aucune couche active, rien d'affiché, aucun mode.
  setActiveLayer(id, kind) {
    // Choisir une couche met fin au dessin en cours (phase 12).
    this.sketches?.onLayerActivated();
    this.activeLayerId = id == null ? null : String(id);
    this.activeLayerKind = kind;
    const buttons = this.hasLayerNoneTarget ? [...this.layerNameTargets, this.layerNoneTarget] : this.layerNameTargets;
    buttons.forEach((button) => {
      const active =
        button === this.layerNoneTarget ? this.activeLayerId === null : button.dataset.layerId === this.activeLayerId;
      button.classList.toggle('bg-teal-50', active);
      button.classList.toggle('font-medium', active);
      button.classList.toggle('text-4s-main', active);
      button.setAttribute('aria-current', active ? 'true' : 'false');
    });
    // Une couche à la fois : la choisie s'affiche, les autres s'effacent, et
    // les réglages propres à une couche (fils résolus, relevés, « à tracer »)
    // ne se montrent qu'avec elle.
    this.showOnlyLayer(this.activeLayerId);
    this.element.querySelectorAll('[data-layer-extra]').forEach((element) => {
      element.classList.toggle('hidden', element.dataset.layerExtra !== kind);
    });
    this.writeActiveLayer(this.activeLayerId ?? NO_LAYER);
    if (this.hasPanelActiveTarget) {
      const name = this.layerNameTargets.find((b) => b.dataset.layerId === this.activeLayerId)?.textContent.trim();
      this.panelActiveTarget.textContent = name ? `· ${name}` : '';
    }
    this.updateModeBar();

    const editable = ['management', 'venues', 'welcome', 'network'].includes(kind) && this.geomanReady;
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
    this.comments?.onActivate(kind);
    this.biodiversity?.onActivate(kind);
    // Changer de couche change de mode de recherche : la recherche s'efface.
    this.search?.onActivate(id, kind);
    // La légende des zones d'accueil (phase 4) accompagne la couche active.
    if (this.hasWelcomeLegendTarget) {
      this.welcomeLegendTarget.classList.toggle('hidden', kind !== 'welcome');
      this.welcomeLegendTarget.classList.toggle('flex', kind === 'welcome');
    }
  }

  // La barre du mode actif (téléphone) : ce qu'elle propose suit la couche
  // active, et elle s'efface devant le tiroir de placement.
  updateModeBar() {
    if (!this.hasModeBarTarget) return;
    let shown = false;
    this.modeBarTarget.querySelectorAll('[data-mode-kind]').forEach((element) => {
      const match = element.dataset.modeKind === this.activeLayerKind;
      element.classList.toggle('hidden', !match);
      element.classList.toggle('flex', match);
      shown ||= match;
    });
    const visible = shown && !this.placement?.drawerOpen;
    this.modeBarTarget.classList.toggle('hidden', !visible);
    this.modeBarTarget.classList.toggle('flex', visible);
  }

  useTool(event) {
    // Un outil Geoman éteint la règle (phase 14).
    this.measure?.stop();
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
        pathOptions: this.featureStyle(
          {
            geometry: { type: { Polygon: 'Polygon', Line: 'LineString' }[tool] || 'Point' },
            properties: { layer_id: this.activeLayerId },
          },
          false
        ),
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
    // Sur une couche réseau (phase 9), un point est un nœud et une ligne un tracé.
    const kinds =
      this.activeLayerKind === 'network'
        ? { Point: 'node', LineString: 'line' }
        : { Point: 'point', LineString: 'path', Polygon: 'zone' };
    const kind = kinds[this.pendingGeometry.type] || 'point';
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
    // Le point d'une plante ouvre la fiche de la plante (phase 7).
    const plantId = this.findFeatureLayer(String(id))?.layer?.feature?.properties?.plant_id;
    this.openPanel(plantId && this.hasPlantUrlValue ? this.plantUrl(plantId) : this.featureUrl(id));
  }

  plantUrl(id) {
    return this.plantUrlValue.replace('__ID__', encodeURIComponent(id));
  }

  placeUrl(id) {
    return this.placeUrlValue.replace('__ID__', encodeURIComponent(id));
  }

  unplaceUrl(id) {
    return this.unplaceUrlValue.replace('__ID__', encodeURIComponent(id));
  }

  // ── Mode Placement (phase 7) : actions du tiroir, du bandeau et de la fiche,
  // déléguées à `PlantPlacement` (utils/map_placement.js). ─────────────────

  openPlacement() {
    this.placement.open();
  }

  // « Nouvelle plante » (panneau des couches, tiroir de placement) : la fiche
  // vide, dans la zone filtrée du tiroir s'il est ouvert. La couche Plantes
  // s'affiche : c'est là que la plante sera posée.
  newPlant() {
    if (!this.hasNewPlantUrlValue) return;
    this.placement?.cancel();
    this.placement?.showPlantsLayer();
    const url = new URL(this.newPlantUrlValue, window.location.origin);
    const zone = this.placement?.zone;
    if (zone) url.searchParams.set('zone', zone);
    this.selectedFeatureId = null;
    this.highlightSelection();
    this.openPanel(url.pathname + url.search);
  }

  // Phase 13 : une ligne de la liste des relevés centre la carte sur le relevé
  // et ouvre sa fiche.
  focusObservation(event) {
    this.biodiversity?.focus(event.currentTarget.dataset.featureId);
  }

  // Phase 11 : « Masquer les résolus », sous la couche Commentaires.
  toggleResolvedComments(event) {
    this.comments?.toggleResolved(event.currentTarget.checked);
  }

  closePlacement() {
    this.placement.close();
  }

  pickPlant(event) {
    this.placement.pick(event.currentTarget.dataset);
  }

  cancelPlacement() {
    this.placement.cancel();
  }

  placementGps() {
    this.placement.startGps();
  }

  confirmGpsPlacement() {
    this.placement.confirmGps();
  }

  undoPlacement() {
    this.placement.undo();
  }

  openLastPlaced() {
    this.placement.openLast();
  }

  adjustLastPlaced() {
    this.placement.adjustLast();
  }

  dismissLastPlaced() {
    this.placement.dismissLast();
  }

  // Depuis la fiche : « Déplacer » (glisser) et « Placer ici (GPS) » pour une
  // plante placée ; « Placer sur la carte » et « Je suis devant » sinon.
  movePlant(event) {
    this.placement.startMove(event.currentTarget.dataset);
  }

  gpsPlacePlant(event) {
    const { dataset } = event.currentTarget;
    if (dataset.featureId) {
      this.placement.startMove(dataset, { gps: true });
    } else {
      this.placement.pick(dataset, { fromPanel: true });
      this.placement.startGps();
    }
  }

  placePlantFromPanel(event) {
    this.placement.pick(event.currentTarget.dataset, { fromPanel: true });
  }

  highlightSelection() {
    Object.values(this.featureLayers || {}).forEach((group) => {
      group.eachLayer((layer) => {
        const selected = String(layer.featureId) === String(this.selectedFeatureId);
        if (layer.labelSelected !== selected) {
          layer.labelSelected = selected;
          syncPointLabel(layer);
        }
        if (layer.setStyle) layer.setStyle(this.featureStyle(layer.feature, selected));
        if (layer.setRadius && layer.feature?.geometry?.type === 'Point') {
          layer.setRadius(selected ? 10 : 8);
        }
        if (layer.setIcon && this.isWelcome(layer.feature)) {
          layer.setIcon(welcomeIcon(L, welcomeProperties(layer.feature).icon, selected));
        }
        // Seules les pastilles dont l'état change sont redessinées : une couche
        // de plusieurs centaines de plantes ne se recrée pas à chaque clic.
        if (layer.setIcon && isPlantFeature(layer.feature) && layer.plantSelected !== selected) {
          layer.plantSelected = selected;
          layer.setIcon(plantIcon(L, layer.feature, selected));
          layer.setZIndexOffset(selected ? 1000 : layer.feature.properties?.dead ? -100 : 0);
        }
        if (layer.setIcon && isNetworkFeature(layer.feature) && layer.networkSelected !== selected) {
          layer.networkSelected = selected;
          layer.setIcon(networkNodeIcon(L, layer.feature, selected));
          layer.setZIndexOffset(selected ? 1000 : 200);
        }
        this.comments?.highlight(layer, selected);
        this.biodiversity?.highlight(layer, selected);
      });
    });
    // `setIcon` remplace l'élément du marqueur : la vue « ce mois-ci » doit
    // reposer ses classes.
    this.applyMonthFocus();
  }

  openPanel(url) {
    if (!this.hasFeatureFrameTarget) return;
    // La fiche prend tout l'écran d'un téléphone : à sa fermeture, on retrouve
    // la carte, pas le panneau des couches.
    this.collapsePanelOnPhone();
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
      this.biodiversity?.onDeleted(layerId);
      return;
    }

    const panel = this.featureFrameTarget.querySelector('[data-feature-panel]');
    if (this.hasPanelContainerTarget) this.panelContainerTarget.classList.toggle('hidden', !panel);
    if (!panel) return;

    // Plante créée (« Nouvelle plante ») : une de plus à placer.
    if (panel.dataset.plantCreated) {
      delete panel.dataset.plantCreated;
      this.placement?.bumpCount(1);
    }

    // Plante retirée de la carte (phase 7) : la fiche reste ouverte, son point
    // disparaît de la couche rechargée.
    if (panel.dataset.layerReload) {
      const layerId = panel.dataset.layerReload;
      delete panel.dataset.layerReload;
      this.selectedFeatureId = null;
      this.placement?.bumpCount(1);
      this.loadLayer(layerId).then(() => this.highlightSelection());
      return;
    }

    const field = this.geometryField();
    if (field && !field.value && this.pendingGeometry) field.value = JSON.stringify(this.pendingGeometry);

    if (panel.dataset.featureSaved === 'true' && panel.dataset.featureId) {
      // Enregistré : l'objet vit désormais dans la couche rechargée, le tracé
      // provisoire n'a plus de raison d'être.
      const id = panel.dataset.featureId;
      delete panel.dataset.featureSaved;
      this.discardPending();
      this.biodiversity?.onSaved(panel);
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

  // ── Carnet de gestion (epic #348, phase 6) ────────────────────────────────
  //
  // `/map?feature=<id>` : le lien du carnet. La carte se centre sur l'objet,
  // rallume et active sa couche, et ouvre sa fiche. Le serveur ne transmet que
  // l'id d'un objet vivant ; un objet absent des couches chargées (couche en
  // échec réseau) est ignoré sans bruit.

  focusFeature() {
    const id = this.focusFeatureValue ? String(this.focusFeatureValue) : null;
    const found = id && this.findFeatureLayer(id);
    if (!found) return;
    const { layer, layerId } = found;

    const toggle = this.layerToggleTargets.find((t) => t.dataset.layerId === String(layerId));
    if (toggle && !toggle.checked) {
      toggle.checked = true;
      toggle.dispatchEvent(new Event('change'));
    }
    const kind = this.layerKinds[String(layerId)];
    if (kind) this.setActiveLayer(layerId, kind);

    // Sur grand écran, le panneau des couches couvre la gauche, la barre
    // d'outils le haut, la barre de date le bas et la fiche la droite : l'objet
    // se centre dans ce qui reste visible.
    const wide = window.matchMedia('(min-width: 768px)').matches;
    const padding = {
      paddingTopLeft: wide ? [300, 90] : [40, 40],
      paddingBottomRight: wide ? [420, 110] : [40, 40],
      maxZoom: 19,
    };
    if (layer.getBounds) this.map.fitBounds(layer.getBounds(), padding);
    else if (layer.getLatLng) this.map.setView(layer.getLatLng(), Math.max(this.map.getZoom(), 19));

    if (this.isVenue(layer.feature)) this.selectVenue(layer.featureId);
    else this.selectFeature(layer.featureId);
  }

  findFeatureLayer(id) {
    for (const [layerId, group] of Object.entries(this.featureLayers || {})) {
      let match = null;
      group.eachLayer((layer) => {
        if (String(layer.featureId) === id) match = layer;
      });
      if (match) return { layer: match, layerId };
    }
    return null;
  }

  // Vue « ce mois-ci » : les objets porteurs d'une tâche du mois en cours
  // ressortent, les autres s'estompent (préfigure la recherche, phase 14). Des
  // classes CSS plutôt que `setStyle` : la sélection d'un objet réécrit son
  // style, elle ne touche pas à ses classes.
  async toggleMonthFocus(event) {
    const checkbox = event.target;
    this.monthFocus = null;
    if (checkbox.checked && this.hasCurrentTasksUrlValue) {
      const response = await fetch(this.currentTasksUrlValue, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      if (!response.ok) {
        checkbox.checked = false;
        this.showNotice('Les tâches du mois ne se chargent pas — réessayez.');
        return;
      }
      const data = await response.json();
      // Décochée pendant le chargement : on n'applique rien.
      if (!checkbox.checked || !this.map) return;
      this.monthFocus = new Set((data.feature_ids || []).map(String));
      if (this.monthFocus.size === 0) this.showNotice(`Aucune tâche en ${String(data.month_name).toLowerCase()}.`);
    }
    this.applyMonthFocus();
  }

  applyMonthFocus() {
    const focus = this.monthFocus;
    Object.values(this.featureLayers || {}).forEach((group) => {
      group.eachLayer((layer) => {
        const inFocus = Boolean(focus) && focus.has(String(layer.featureId));
        const dimmed = Boolean(focus) && !inFocus;
        const element = layer.getElement?.();
        if (element) {
          element.classList.toggle('map-month-task', inFocus);
          element.classList.toggle('map-month-dimmed', dimmed);
        }
        layer.getTooltip?.()?.getElement?.()?.classList.toggle('map-month-dimmed', dimmed);
      });
    });
    // Mêmes éléments recréés, même besoin pour la recherche (phase 14).
    this.search?.apply();
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

  // Un objet de la couche Accueil (phase 4) : zone colorée selon l'accès, point
  // à icône. La couche se reconnaît à son kind, noté au chargement.
  isWelcome(feature) {
    const layerId = feature?.properties?.layer_id;
    return layerId != null && this.layerKinds?.[String(layerId)] === 'welcome';
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
    this.search?.onDateChange();

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

  readActiveLayer() {
    try {
      return window.localStorage.getItem(ACTIVE_LAYER_KEY);
    } catch {
      return null;
    }
  }

  writeActiveLayer(id) {
    try {
      window.localStorage.setItem(ACTIVE_LAYER_KEY, String(id));
    } catch {
      // Navigation privée ou stockage plein : l'état ne survit pas, rien de grave.
    }
  }
}
