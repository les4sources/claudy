// Les plantes nourricières sur la carte (epic #348, phase 7).
//
// Chaque plante placée est une pastille ronde : sa couleur dit sa santé, son
// pictogramme sa strate (visible à partir du zoom 17), et une plante morte
// devient une petite pastille grise. Les couleurs et les tracés sont ceux de la
// fiche (`PlantsHelper`) — garder les deux en phase.

export const PLANT_HEALTH_COLORS = {
  healthy: '#1F5F4A',
  worrying: '#E0A351',
  sick: '#C2553F',
};
export const PLANT_UNKNOWN_COLOR = '#7C8F86';
export const PLANT_DEAD_COLOR = '#A8A29E';

// Tracés 24 × 24, trait `currentColor`. Clés = `Plant::STRATA` côté Rails.
const POLLARD = '<path d="M10 22V12h4v10"/><path d="M10 12 6 4M12 12V3M14 12l4-8"/>';
const CLIMBER = '<path d="M12 22V3"/><path d="M12 7c3 0 4 2 4 4s-2 3-4 3M12 14c-3 0-4 2-4 3.5"/>';
export const STRATUM_GLYPHS = {
  tree: '<circle cx="12" cy="9" r="6"/><path d="M12 15v7"/>',
  coppice: '<circle cx="8" cy="9" r="4"/><circle cx="16" cy="9" r="4"/><path d="M8 13l4 9 4-9"/>',
  pollard: POLLARD,
  food_pollard: POLLARD,
  espalier: '<path d="M12 22V4M12 9H5M12 9h7M12 15H6M12 15h6"/>',
  shrub: '<path d="M4 18a4 4 0 0 1 3-6 5 5 0 0 1 10 0 4 4 0 0 1 3 6z"/><path d="M12 18v4"/>',
  subshrub: '<path d="M6 19a3 3 0 0 1 3-5 3 3 0 0 1 6 0 3 3 0 0 1 3 5z"/><path d="M12 19v3"/>',
  herbaceous: '<path d="M12 22V10"/><path d="M12 14c-4 0-6-3-6-7 4 0 6 3 6 7zM12 12c0-4 2-7 6-7 0 4-2 7-6 7z"/>',
  climber: CLIMBER,
  vine: CLIMBER,
  groundcover: '<path d="M2 17c3-4 5-4 7 0 2-4 4-4 6 0 2-4 4-4 7 0"/><path d="M2 21h20"/>',
  aquatic: '<path d="M12 3c-3 4-6 7-6 11a6 6 0 0 0 12 0c0-4-3-7-6-11z"/>',
};
const DEFAULT_GLYPH = '<circle cx="12" cy="12" r="3"/>';

export function isPlantFeature(feature) {
  return feature?.properties?.feature_kind === 'plant';
}

export function plantColor(properties) {
  if (properties?.dead) return PLANT_DEAD_COLOR;
  return PLANT_HEALTH_COLORS[properties?.health] || PLANT_UNKNOWN_COLOR;
}

export function plantIcon(L, feature, selected = false) {
  const props = feature?.properties || {};
  const dead = Boolean(props.dead);
  const base = dead ? 14 : 22;
  const size = selected ? base + 8 : base;
  const glyph = STRATUM_GLYPHS[props.stratum] || DEFAULT_GLYPH;
  const classes = ['map-plant-pin'];
  if (dead) classes.push('map-plant-pin--dead');
  if (selected) classes.push('map-plant-pin--selected');
  return L.divIcon({
    className: 'map-plant-pin-wrapper',
    html:
      `<span class="${classes.join(' ')}" style="--plant-color: ${plantColor(props)}">` +
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ` +
      `stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph}</svg></span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    tooltipAnchor: [size / 2, 0],
  });
}

// Une plante morte passe sous les vivantes quand elles se chevauchent.
export function plantMarker(L, feature, latlng) {
  return L.marker(latlng, {
    icon: plantIcon(L, feature),
    riseOnHover: true,
    zIndexOffset: feature?.properties?.dead ? -100 : 0,
    title: feature?.properties?.name || '',
  });
}
