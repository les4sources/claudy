import { Controller } from '@hotwired/stimulus';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

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
  ];

  static values = {
    tilesUrl: String,
    layerKey: String,
    bounds: Array,
    center: Array,
    minZoom: { type: Number, default: 12 },
    maxZoom: { type: Number, default: 20 },
    hasRelief: { type: String, default: 'false' },
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

    // Leaflet mesure son conteneur au montage. Dans une page Turbo le conteneur
    // n'a pas toujours sa taille finale à ce moment-là : sans ce recalcul, la
    // carte s'affiche en tuiles grises sur un quart de l'écran.
    requestAnimationFrame(() => this.map.invalidateSize());
  }

  disconnect() {
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
}
