import { Controller } from '@hotwired/stimulus';

// Le gîte du séjour : `ember` du thème (MapFeature::STAY_LODGING_COLOR).
const EMBER = '#C97B3D';
const BLANK_TILE = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

// La carte du domaine pour les hôtes (epic #348, phase 4).
//
// La petite sœur de `map_controller.js` : même fond, mêmes couleurs de zones
// (`~/utils/map_welcome`), mais rien à éditer — la couche Accueil, le gîte du
// séjour surligné et centré, une bulle au clic, et « Ma position ».
//
// Leaflet n'est chargé QUE sur cette page : l'import est dynamique, Vite en
// fait un morceau à part, et les autres pages publiques ne le paient pas.
export default class extends Controller {
  static targets = ['canvas', 'locateButton', 'notice'];

  static values = {
    tilesUrl: String,
    bounds: Array,
    center: Array,
    minZoom: { type: Number, default: 12 },
    maxZoom: { type: Number, default: 20 },
    welcome: Object,
    lodgings: Object,
    locateError: String,
  };

  async connect() {
    const [{ default: L }, welcome] = await Promise.all([
      import('leaflet'),
      import('~/utils/map_welcome'),
      import('leaflet/dist/leaflet.css'),
      import('~/stylesheets/map.css'),
    ]);
    // La page a pu être quittée pendant le chargement.
    if (!this.element.isConnected || this.map) return;

    this.L = L;
    const bounds = this.boundsValue.length === 2 ? L.latLngBounds(this.boundsValue) : null;

    this.map = L.map(this.canvasTarget, {
      center: this.centerValue.length === 2 ? this.centerValue : [50.3414088, 4.9078535],
      zoom: 17,
      minZoom: this.minZoomValue,
      maxZoom: this.maxZoomValue,
      maxBounds: bounds ? bounds.pad(0.25) : undefined,
      zoomControl: false,
      attributionControl: false,
    });
    L.control.zoom({ position: 'topright' }).addTo(this.map);

    L.tileLayer(this.tilesUrlValue.replace('{kind}', 'rgb'), {
      minZoom: this.minZoomValue,
      maxZoom: this.maxZoomValue,
      errorTileUrl: BLANK_TILE,
      bounds: bounds || undefined,
      keepBuffer: 4,
    }).addTo(this.map);

    L.geoJSON(this.welcomeValue, {
      style: (feature) => welcome.welcomeStyle(feature),
      pointToLayer: (feature, latlng) => welcome.welcomeMarker(L, feature, latlng),
      onEachFeature: (feature, layer) => this.bindPopup(feature, layer),
    }).addTo(this.map);

    // Le gîte du séjour, par-dessus les zones : c'est lui qu'on cherche en
    // arrivant.
    const lodgings = L.geoJSON(this.lodgingsValue, {
      style: { color: EMBER, weight: 4, fillColor: EMBER, fillOpacity: 0.35 },
      onEachFeature: (feature, layer) => {
        const name = feature.properties?.name;
        if (name) layer.bindTooltip(name, { permanent: true, direction: 'center', className: 'map-feature-label' });
      },
    }).addTo(this.map);

    if (lodgings.getLayers().length > 0) {
      // Zoom 18 au plus : le gîte au centre, et assez d'alentours pour s'y repérer.
      this.map.fitBounds(lodgings.getBounds(), { padding: [60, 60], maxZoom: 18 });
    } else if (bounds) {
      this.map.fitBounds(bounds);
    }

    this.locating = false;
    this.map.on('locationfound', (event) => this.onLocationFound(event));
    this.map.on('locationerror', () => this.onLocationError());

    requestAnimationFrame(() => this.map?.invalidateSize());
  }

  disconnect() {
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }

  // La bulle d'une zone ou d'un point : le nom, puis la description. Construite
  // en DOM (`textContent`), jamais en HTML concaténé : ces textes sont saisis
  // par l'équipe, ils ne doivent rien pouvoir injecter.
  bindPopup(feature, layer) {
    const { name, description } = feature.properties || {};
    if (!name && !description) return;

    const content = document.createElement('div');
    if (name) {
      const title = document.createElement('strong');
      title.textContent = name;
      content.appendChild(title);
    }
    if (description) {
      const text = document.createElement('p');
      text.textContent = description;
      content.appendChild(text);
    }
    layer.bindPopup(content, { className: 'map-welcome-popup', maxWidth: 260 });
  }

  toggleLocate() {
    if (!this.map) return;

    this.locating = !this.locating;
    this.locateButtonTarget.setAttribute('aria-pressed', String(this.locating));
    this.locateButtonTarget.classList.toggle('text-forest', this.locating);

    if (this.locating) {
      this.map.locate({ watch: true, enableHighAccuracy: true, setView: true, maxZoom: 19 });
    } else {
      this.map.stopLocate();
      this.clearLocation();
    }
  }

  onLocationFound(event) {
    const L = this.L;
    this.clearLocation();
    this.locationMarker = L.circleMarker(event.latlng, {
      radius: 7,
      color: '#ffffff',
      weight: 2,
      fillColor: '#024442',
      fillOpacity: 1,
    }).addTo(this.map);
    this.locationCircle = L.circle(event.latlng, {
      radius: event.accuracy,
      color: '#024442',
      weight: 1,
      fillOpacity: 0.08,
    }).addTo(this.map);
  }

  onLocationError() {
    this.locating = false;
    this.locateButtonTarget.setAttribute('aria-pressed', 'false');
    this.locateButtonTarget.classList.remove('text-forest');
    this.showNotice(this.locateErrorValue);
  }

  clearLocation() {
    [this.locationMarker, this.locationCircle].forEach((layer) => {
      if (layer) this.map.removeLayer(layer);
    });
    this.locationMarker = null;
    this.locationCircle = null;
  }

  showNotice(message) {
    if (!this.hasNoticeTarget || !message) return;

    this.noticeTarget.textContent = message;
    this.noticeTarget.classList.remove('hidden');
    clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => this.noticeTarget.classList.add('hidden'), 4000);
  }
}
