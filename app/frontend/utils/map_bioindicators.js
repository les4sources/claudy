// Les relevés de plantes bio-indicatrices sur la carte.
//
// Même mécanique que la Biodiversité (`BiodiversityMode`) : la couche active,
// toucher la carte ou « À ma position » ouvre la fiche d'un nouveau relevé
// photo, créé à « Enregistrer ». Seuls changent la couche, la fiche, la liste
// et le marqueur : un triangle à la couleur de l'état du sol (vert équilibré,
// jaune en cours de dégradation, rouge dégradé), une pastille grise pointillée
// tant que le relevé attend son analyse.
//
// MÊMES couleurs que `MapBioindicatorsHelper` (la liste et la fiche).

import { BiodiversityMode } from '~/utils/map_biodiversity';

export const AGRONOMY_COLORS = { degraded: '#B42318', degrading: '#D9A21B', balanced: '#2E7D4F' };
const PENDING_COLOR = '#78716C';
const NEW_COLOR = '#0B3D3A';
const TRIANGLE = '<path d="M12 4 21 19.5H3Z" fill="currentColor" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>';

export function isBioindicatorFeature(feature) {
  return feature?.properties?.feature_kind === 'bioindicator';
}

// `state` : 'new' (marqueur provisoire), 'to_analyze', ou l'état agronomique.
export function bioindicatorIcon(leaflet, state, selected = false) {
  const size = selected ? 36 : 30;
  const color = AGRONOMY_COLORS[state] || (state === 'new' ? NEW_COLOR : PENDING_COLOR);
  const classes = ['map-observation-pin', 'map-bioindicator-pin'];
  if (selected) classes.push('map-observation-pin--selected');
  if (!AGRONOMY_COLORS[state]) classes.push('map-observation-pin--pending');
  const inner = AGRONOMY_COLORS[state]
    ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">${TRIANGLE}</svg>`
    : state === 'new' ? '+' : '?';
  return leaflet.divIcon({
    className: 'map-observation-pin-wrapper',
    html: `<span class="${classes.join(' ')}" style="--observation-color: ${color}">${inner}</span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    tooltipAnchor: [size / 2, 0],
  });
}

function stateOf(feature) {
  const props = feature?.properties || {};
  if (props.status === 'to_analyze' || !props.agronomy) return 'to_analyze';
  return props.agronomy;
}

export function bioindicatorMarker(leaflet, feature, latlng) {
  const props = feature?.properties || {};
  return leaflet.marker(latlng, {
    icon: bioindicatorIcon(leaflet, stateOf(feature)),
    riseOnHover: true,
    zIndexOffset: 150,
    title: [props.name, props.observed_on, props.status === 'to_analyze' ? 'à analyser' : null].filter(Boolean).join(' — '),
  });
}

export const BIOINDICATOR_MODE = {
  kind: 'bioindicators',
  newUrlKey: 'newBioindicatorUrl',
  listFrame: 'map_bioindicators',
  panelFlag: 'bioindicatorPanel',
  notice: 'Touchez la carte, ou « À ma position », pour photographier les plantes bio-indicatrices.',
  isFeature: isBioindicatorFeature,
  icon: (leaflet, feature, selected) => bioindicatorIcon(leaflet, stateOf(feature), selected),
  pendingIcon: (leaflet) => bioindicatorIcon(leaflet, 'new', true),
};

export function bioindicatorMode(controller) {
  return new BiodiversityMode(controller, BIOINDICATOR_MODE);
}
