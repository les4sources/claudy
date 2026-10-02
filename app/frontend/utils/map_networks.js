// Les réseaux sur la carte (epic #348, phase 9) : eau, électricité, ethernet.
//
// Un tracé prend la couleur de son réseau et une épaisseur selon son calibre ;
// un nœud est une pastille ronde de la couleur du réseau qui porte l'icône de
// son type (vanne, tableau, switch…). La couleur arrive dans le JSON de chaque
// objet (`properties.color`, lue sur `settings.color` de la couche) ; celles-ci
// ne sont que le repli, les mêmes que `MapLayer::NETWORKS` côté Rails.

import { unifiBadgeHtml } from './map_unifi';

export const NETWORK_COLORS = {
  water: '#2563EB',
  electric: '#D97706',
  ethernet: '#7C3AED',
};
// Les noms des nœuds et des tracés n'apparaissent qu'à partir du zoom 19 : un
// réseau, c'est beaucoup de petits objets serrés.
export const NETWORK_LABEL_MIN_ZOOM = 19;
// Clés = `MapFeature::GAUGES` côté Rails.
const GAUGE_WEIGHTS = { thin: 2, medium: 4, thick: 7 };

// Tracés 24 × 24, trait `currentColor`. Clés = `MapLayer::NODE_TYPES` côté
// Rails (le compteur `meter` sert à l'eau et à l'électricité).
const NODE_GLYPHS = {
  // Eau
  source: '<path d="M12 3c-3 4-5 6.5-5 9a5 5 0 0 0 10 0c0-2.5-2-5-5-9z"/><path d="M3 21c2-1.5 4-1.5 6 0s4 1.5 6 0 4-1.5 6 0"/>',
  catchment: '<path d="M4 4v6a8 8 0 0 0 16 0V4"/><path d="M12 8v7M9 12l3 3 3-3"/>',
  cistern: '<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/>',
  valve: '<circle cx="12" cy="12" r="7"/><path d="M12 5v14M5 12h14"/><circle cx="12" cy="12" r="1.5"/>',
  meter: '<circle cx="12" cy="13" r="8"/><path d="M12 13l4-4M8 17h8"/>',
  tap: '<path d="M4 9h9a4 4 0 0 1 4 4v1"/><path d="M8 9V5M5 5h6"/><path d="M17 18v3"/>',
  manhole: '<circle cx="12" cy="12" r="8"/><path d="M6 9h12M5 12h14M6 15h12"/>',
  // Électricité
  panel: '<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M9 7v4M12 7v4M15 7v4M9 15h6"/>',
  outlet: '<circle cx="12" cy="12" r="8"/><path d="M9.5 10v3M14.5 10v3"/>',
  breaker: '<rect x="7" y="3" width="10" height="18" rx="1.5"/><path d="M12 7v5"/><rect x="10" y="12" width="4" height="4"/>',
  lighting: '<path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.5 1 2.5h6c0-1 .3-1.8 1-2.5A6 6 0 0 0 12 3z"/>',
  // Ethernet
  switch: '<rect x="3" y="7" width="18" height="10" rx="1.5"/><path d="M6 12h1.5M9.5 12H11M13 12h1.5M16.5 12H18"/>',
  access_point: '<path d="M5 10a10 10 0 0 1 14 0M8 13.5a5.5 5.5 0 0 1 8 0"/><circle cx="12" cy="17" r="1.5"/>',
  wall_jack: '<rect x="5" y="5" width="14" height="14" rx="2"/><path d="M9 15v-4h1.5V9h3v2H15v4z"/>',
  router: '<rect x="3" y="12" width="18" height="7" rx="1.5"/><path d="M7 12V6M17 12V6M7 15.5h1M11 15.5h1"/>',
  rack: '<rect x="5" y="3" width="14" height="18" rx="1"/><path d="M5 8h14M5 13h14M5 18h14M8 5.5h.01M8 10.5h.01M8 15.5h.01"/>',
  fiber_box: '<rect x="4" y="6" width="16" height="12" rx="2"/><path d="M8 12c2-3 6-3 8 0"/><circle cx="12" cy="12" r="1"/>',
};
const DEFAULT_GLYPH = '<circle cx="12" cy="12" r="3"/>';

export function isNetworkFeature(feature) {
  return Boolean(feature?.properties?.network);
}

export function networkColor(properties) {
  return properties?.color || NETWORK_COLORS[properties?.network] || '#475569';
}

// Style Leaflet d'un objet de réseau. `color` vient du JSON, ou de la couche
// active pour ce qu'on est en train de dessiner.
export function networkStyle(feature, color, selected = false) {
  if (feature?.geometry?.type === 'LineString') {
    const weight = GAUGE_WEIGHTS[feature?.properties?.gauge] || GAUGE_WEIGHTS.medium;
    return {
      color,
      weight: selected ? weight + 3 : weight,
      opacity: 0.95,
      lineCap: 'round',
      lineJoin: 'round',
    };
  }
  // Le point en cours de dessin (Geoman CircleMarker), avant sa pastille.
  return { radius: selected ? 10 : 8, color: '#ffffff', weight: 2, fillColor: color, fillOpacity: 1 };
}

export function networkNodeIcon(L, feature, selected = false) {
  const props = feature?.properties || {};
  const size = selected ? 30 : 22;
  const glyph = NODE_GLYPHS[props.node_type] || DEFAULT_GLYPH;
  const classes = ['map-network-pin'];
  if (selected) classes.push('map-network-pin--selected');
  return L.divIcon({
    className: 'map-network-pin-wrapper',
    html:
      // `position: relative` : la pastille de statut UniFi (phase 10) se cale
      // dans le coin de l'icône.
      `<span class="${classes.join(' ')}" style="--network-color: ${networkColor(props)}; position: relative">` +
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ` +
      `stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph}</svg>` +
      `${unifiBadgeHtml(props)}${nonPotableBadgeHtml(props)}</span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    tooltipAnchor: [size / 2, 0],
  });
}

export function networkNodeMarker(L, feature, latlng) {
  const props = feature?.properties || {};
  return L.marker(latlng, {
    icon: networkNodeIcon(L, feature),
    riseOnHover: true,
    // Les nœuds passent au-dessus des tracés et des autres points.
    zIndexOffset: 200,
    title: [props.name, props.node_type_label, props.water_source_label, props.non_potable && 'non potable']
      .filter(Boolean)
      .join(' — '),
  });
}

// Dans la fiche d'un nœud d'eau, choisir « Robinet » révèle l'origine de
// l'eau ; un autre type la masque (le serveur l'efface alors).
// Choisir une eau non potable révèle l'avertissement sous le champ.
export function handleNodeTypeChange(event) {
  const select = event.target;
  const form = select?.closest('form');
  if (!form) return;
  if (select.name === 'map_feature[node_type]') {
    form.querySelectorAll('[data-water-source-field]').forEach((el) => {
      el.hidden = select.value !== 'tap';
    });
  } else if (select.name === 'map_feature[water_source]') {
    form.querySelectorAll('[data-non-potable-hint]').forEach((el) => {
      el.hidden = !el.dataset.nonPotableHint.split(' ').includes(select.value);
    });
  }
}

// Un robinet d'eau non potable (eau de pluie) : pastille rouge barrée dans le
// coin bas de l'icône, à l'opposé de celle d'UniFi, cerclée de blanc pour se
// lire sur la photo aérienne.
export function nonPotableBadgeHtml(properties) {
  if (!properties?.non_potable) return '';
  return (
    '<span class="map-non-potable" title="Eau non potable" ' +
    'style="position:absolute;bottom:-4px;right:-4px;width:12px;height:12px;border-radius:9999px;' +
    'background:#DC2626;border:2px solid #ffffff;box-shadow:0 0 2px rgba(0,0,0,0.45);' +
    'display:flex;align-items:center;justify-content:center">' +
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8" width="6" height="6" aria-hidden="true">' +
    '<line x1="1" y1="1" x2="7" y2="7" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/></svg></span>'
  );
}
