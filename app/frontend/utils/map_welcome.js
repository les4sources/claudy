// La couche Accueil de la carte du domaine (epic #348, phase 4).
//
// Partagée entre la carte de l'équipe (`map_controller.js`, où l'on trace) et
// la page publique d'un séjour (`public/stay_map_controller.js`, où les hôtes
// lisent) : une zone doit avoir la même couleur des deux côtés, sinon la légende
// ment à l'un des deux.

// Trois couleurs franches, lisibles sur l'orthophoto : vert = on y va,
// rouge = on n'y va pas, ambre = on demande d'abord.
export const ACCESS_COLORS = {
  public: '#2E7D4F',
  private: '#B42318',
  on_request: '#D98E04',
};

const PATH_COLOR = '#8A6F47';

// Icônes des points utiles (trait 24 × 24, `currentColor`). Les clés sont
// celles de `MapFeature::WELCOME_ICONS` côté Rails.
export const WELCOME_ICONS = {
  parking: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 17V7h4a3 3 0 0 1 0 6H9"/>',
  trash: '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>',
  wood: '<circle cx="7" cy="16" r="3"/><circle cx="17" cy="16" r="3"/><circle cx="12" cy="8" r="3"/>',
  oven: '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.07-2.14-.22-4.05 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.15.43-2.29 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>',
  grocery: '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/>',
  disc_golf: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/><path d="M12 3v5M12 16v5"/>',
  meeting_point: '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><path d="M4 22v-7"/>',
  animals: '<circle cx="11" cy="4" r="2"/><circle cx="18" cy="8" r="2"/><circle cx="20" cy="16" r="2"/><path d="M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.05Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z"/>',
  toilets: '<circle cx="7" cy="4" r="2"/><path d="M7 8v13M4 12h6"/><circle cx="17" cy="4" r="2"/><path d="m14 21 3-13 3 13M14.5 17h5"/>',
  water: '<path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
};

// Les propriétés d'un objet : à plat sur la page publique (`as_public_geojson`),
// sous `properties.properties` côté équipe (`as_geojson`).
export function welcomeProperties(feature) {
  const props = feature?.properties || {};
  return { ...(props.properties || {}), ...props };
}

export function welcomeStyle(feature, selected = false) {
  const type = feature?.geometry?.type;
  const weight = selected ? 5 : 2;
  if (type === 'LineString') {
    return { color: PATH_COLOR, weight: selected ? 6 : 4, dashArray: '8 8', lineCap: 'round' };
  }
  const color = ACCESS_COLORS[welcomeProperties(feature).access] || ACCESS_COLORS.public;
  return { color, weight, fillColor: color, fillOpacity: selected ? 0.4 : 0.28 };
}

// Un point utile : une pastille blanche portant son icône, 32 px — assez gros
// pour un doigt sur un téléphone, assez petit pour ne pas cacher le terrain.
export function welcomeIcon(L, key, selected = false) {
  const paths = WELCOME_ICONS[key] || WELCOME_ICONS.info;
  const size = selected ? 38 : 32;
  return L.divIcon({
    className: 'map-welcome-pin-wrapper',
    html:
      `<span class="map-welcome-pin${selected ? ' map-welcome-pin--selected' : ''}">` +
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ` +
      `stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg></span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -size / 2],
  });
}

export function welcomeMarker(L, feature, latlng) {
  return L.marker(latlng, { icon: welcomeIcon(L, welcomeProperties(feature).icon) });
}
