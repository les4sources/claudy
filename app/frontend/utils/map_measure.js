// L'outil Mesure de la carte (epic #348, phase 14), disponible dans tous les
// modes.
//
// La règle allumée, chaque clic pose un sommet : la distance cumulée suit le
// curseur PENDANT le tracé. Double-clic (ou « Surface ») ferme en polygone et
// donne la surface ; « Terminer » (ou Entrée) garde une ligne et sa distance.
// Chaque mesure finie reste affichée dans une bulle ; on en fait autant qu'on
// veut, « Effacer les mesures » (ou Échap sans tracé en cours) les retire.
//
// Hors Geoman : l'outil coupe le dessin Geoman en cours, et reprendre un outil
// Geoman éteint la règle. Rien n'est enregistré : une mesure vit dans la page.
//
// Calcul géodésique maison, sans dépendance : haversine pour les longueurs,
// aire d'un polygone sur la sphère pour les surfaces (la formule de turf/area,
// Chamberlain & Duquette), R = 6 371 008,8 m — le même rayon que
// `MapFeature::EARTH_RADIUS_M` côté serveur. Les fonctions de calcul sont pures
// et exportées : pas d'import ici, Leaflet est prêté par le contrôleur.

export const EARTH_RADIUS_M = 6371008.8;

const toRad = (degrees) => (degrees * Math.PI) / 180;

// Distance en mètres entre deux points `{ lat, lng }` (un `L.LatLng` convient).
export function haversineDistance(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

// Longueur d'une polyligne, somme des segments.
export function pathLength(latlngs) {
  let total = 0;
  for (let i = 1; i < latlngs.length; i += 1) total += haversineDistance(latlngs[i - 1], latlngs[i]);
  return total;
}

// Surface en m² d'un polygone sur la sphère. L'anneau peut être fermé (dernier
// point = premier) ou non ; moins de trois sommets distincts = 0.
export function sphericalPolygonArea(latlngs) {
  const ring = latlngs.slice();
  const first = ring[0];
  const last = ring[ring.length - 1];
  if (ring.length > 1 && first.lat === last.lat && first.lng === last.lng) ring.pop();
  const n = ring.length;
  if (n < 3) return 0;
  let total = 0;
  for (let i = 0; i < n; i += 1) {
    const lower = ring[i];
    const middle = ring[(i + 1) % n];
    const upper = ring[(i + 2) % n];
    total += (toRad(upper.lng) - toRad(lower.lng)) * Math.sin(toRad(middle.lat));
  }
  return Math.abs((total * EARTH_RADIUS_M * EARTH_RADIUS_M) / 2);
}

const number = (value, digits) =>
  value.toLocaleString('fr-BE', { minimumFractionDigits: digits, maximumFractionDigits: digits });

// « 742 m », « 1,26 km ».
export function formatDistance(meters) {
  if (meters >= 1000) return `${number(meters / 1000, 2)} km`;
  return `${number(meters, meters < 10 ? 1 : 0)} m`;
}

// « 84 m² », « 12,40 a », « 1,02 ha ».
export function formatArea(squareMeters) {
  if (squareMeters >= 10000) return `${number(squareMeters / 10000, 2)} ha`;
  if (squareMeters >= 100) return `${number(squareMeters / 100, 2)} a`;
  return `${number(squareMeters, 0)} m²`;
}

const COLOR = '#C97B3D'; // `ember` du thème
const SAME_POINT_PX = 6;

export class MeasureTool {
  constructor(controller, L) {
    this.c = controller;
    this.L = L;
    this.active = false;
    this.points = [];
    this.root = controller.element.querySelector('[data-map-measure]');
    if (!this.root) return;
    this.toggleButton = this.root.querySelector('[data-map-measure-toggle]');
    this.actions = this.root.querySelector('[data-map-measure-actions]');
    this.onButton = (event) => {
      if (event.target.closest('[data-map-measure-toggle]')) this.toggle();
      else if (event.target.closest('[data-map-measure-close]')) this.finish(true);
      else if (event.target.closest('[data-map-measure-finish]')) this.finish(false);
      else if (event.target.closest('[data-map-measure-clear]')) this.clearAll();
    };
    this.root.addEventListener('click', this.onButton);
    this.onClick = (event) => this.addPoint(event.latlng);
    this.onMove = (event) => this.preview(event.latlng);
    this.onDblClick = (event) => {
      L.DomEvent.stop(event);
      this.finish(true);
    };
    this.onKeydown = (event) => this.keydown(event);
  }

  destroy() {
    this.stop();
    this.root?.removeEventListener('click', this.onButton);
    this.group?.remove();
  }

  toggle() {
    if (this.active) this.stop();
    else this.start();
  }

  start() {
    const map = this.c.map;
    if (!map || this.active) return;
    // Hors Geoman : la règle coupe le tracé Geoman en cours.
    this.c.disableTools?.();
    this.c.resetTools?.();
    this.active = true;
    this.group ||= this.L.layerGroup().addTo(map);
    this.doubleClickZoom = map.doubleClickZoom.enabled();
    map.doubleClickZoom.disable();
    map.getContainer().classList.add('map-measuring');
    map.on('click', this.onClick);
    map.on('mousemove', this.onMove);
    map.on('dblclick', this.onDblClick);
    document.addEventListener('keydown', this.onKeydown);
    this.c.showNotice?.('Mesure : touchez la carte pour poser des points. Double-clic ferme une surface.');
    this.update();
  }

  stop() {
    if (!this.active) return;
    const map = this.c.map;
    this.cancelCurrent();
    this.active = false;
    if (map) {
      if (this.doubleClickZoom) map.doubleClickZoom.enable();
      map.getContainer().classList.remove('map-measuring');
      map.off('click', this.onClick);
      map.off('mousemove', this.onMove);
      map.off('dblclick', this.onDblClick);
    }
    document.removeEventListener('keydown', this.onKeydown);
    this.update();
  }

  // Un clic sur un objet de la carte pendant la mesure pose un sommet au lieu
  // d'ouvrir sa fiche (appelé par `bindFeature`).
  interceptFeatureClick(event) {
    if (!this.active) return false;
    this.L.DomEvent.stopPropagation(event);
    this.addPoint(event.latlng);
    return true;
  }

  keydown(event) {
    if (event.defaultPrevented) return;
    const field = event.target.closest?.('input, textarea, select, [contenteditable]');
    if (field) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      if (this.points.length) this.cancelCurrent();
      else this.clearAll();
    } else if (event.key === 'Enter' && this.points.length) {
      event.preventDefault();
      this.finish(false);
    }
  }

  addPoint(latlng) {
    if (!latlng) return;
    this.points.push(latlng);
    const L = this.L;
    if (!this.line) {
      this.line = L.polyline([], { color: COLOR, weight: 3, interactive: false }).addTo(this.group);
      this.rubber = L.polyline([], { color: COLOR, weight: 2, dashArray: '4 6', interactive: false }).addTo(this.group);
      this.vertices = L.layerGroup().addTo(this.group);
    }
    this.line.setLatLngs(this.points);
    L.circleMarker(latlng, { radius: 4, color: '#fff', weight: 2, fillColor: COLOR, fillOpacity: 1, interactive: false })
      .addTo(this.vertices);
    this.preview(latlng);
  }

  // La mesure en cours suit le curseur : distance cumulée, et la surface dès
  // trois sommets.
  preview(cursor) {
    if (!this.points.length || !cursor) return;
    const path = [...this.points, cursor];
    this.rubber.setLatLngs([this.points[this.points.length - 1], cursor]);
    let text = formatDistance(pathLength(path));
    if (path.length >= 3) text += ` · ${formatArea(sphericalPolygonArea(path))}`;
    if (!this.cursorTip) {
      this.cursorTip = this.L.tooltip({
        permanent: true,
        direction: 'right',
        offset: [14, 0],
        className: 'map-measure-tooltip',
        interactive: false,
      });
      this.cursorTip.setLatLng(cursor).setContent(text).addTo(this.c.map);
    } else {
      this.cursorTip.setLatLng(cursor).setContent(text);
    }
  }

  // Termine la mesure en cours : en surface (`asArea`, au moins trois sommets)
  // ou en ligne (au moins deux).
  finish(asArea) {
    this.dropDoubleClickPoints();
    const points = this.points.slice();
    const L = this.L;
    const area = asArea && points.length >= 3;
    if (!area && points.length < 2) {
      if (asArea) this.c.showNotice?.('Une surface demande au moins trois points.');
      return;
    }
    this.cancelCurrent();
    let shape;
    let text;
    if (area) {
      shape = L.polygon(points, { color: COLOR, weight: 2, fillColor: COLOR, fillOpacity: 0.15, interactive: false });
      text = `<strong>${formatArea(sphericalPolygonArea(points))}</strong><br>périmètre ${formatDistance(
        pathLength([...points, points[0]])
      )}`;
    } else {
      shape = L.polyline(points, { color: COLOR, weight: 3, interactive: false });
      text = `<strong>${formatDistance(pathLength(points))}</strong>`;
    }
    shape.addTo(this.group);
    L.tooltip({ permanent: true, direction: 'top', className: 'map-measure-tooltip map-measure-result', interactive: false })
      .setLatLng(area ? shape.getBounds().getCenter() : points[points.length - 1])
      .setContent(text)
      .addTo(this.group);
    this.update();
  }

  // Un double-clic arrive après deux clics au même endroit : ces sommets en
  // double ne doivent ni fausser la surface ni dessiner un segment nul.
  dropDoubleClickPoints() {
    const map = this.c.map;
    while (this.points.length >= 2 && map) {
      const a = map.latLngToContainerPoint(this.points[this.points.length - 1]);
      const b = map.latLngToContainerPoint(this.points[this.points.length - 2]);
      if (a.distanceTo(b) > SAME_POINT_PX) break;
      this.points.pop();
    }
  }

  cancelCurrent() {
    // `removeLayer` du groupe, pas `layer.remove()` : le groupe garderait sinon
    // la référence et croirait porter encore une mesure.
    [this.line, this.rubber, this.vertices].forEach((layer) => layer && this.group?.removeLayer(layer));
    this.cursorTip?.remove();
    this.line = this.rubber = this.vertices = this.cursorTip = null;
    this.points = [];
  }

  clearAll() {
    this.cancelCurrent();
    this.group?.clearLayers();
    this.update();
  }

  update() {
    if (!this.root) return;
    this.toggleButton?.setAttribute('aria-pressed', this.active ? 'true' : 'false');
    this.toggleButton?.classList.toggle('text-4s-main', this.active);
    this.toggleButton?.classList.toggle('ring-2', this.active);
    this.toggleButton?.classList.toggle('ring-orange-300', this.active);
    const hasMeasures = Boolean(this.group?.getLayers().length);
    const show = this.active || hasMeasures;
    this.actions?.classList.toggle('hidden', !show);
    this.actions?.classList.toggle('flex', show);
    this.root.querySelectorAll('[data-map-measure-close], [data-map-measure-finish]').forEach((button) => {
      button.classList.toggle('hidden', !this.active);
    });
  }
}
