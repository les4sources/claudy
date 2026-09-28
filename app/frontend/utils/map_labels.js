// Le libellé d'un point n'est pas permanent (il se recouvrait avec ses
// voisins) : il s'ouvre au survol ou au toucher, et reste ouvert tant que le
// point est épinglé — sélectionné, ou trouvé par la recherche.
export function syncPointLabel(layer) {
  const tooltip = layer.getTooltip?.();
  if (!tooltip || tooltip.options.permanent) return;
  if (layer.labelSelected || layer.labelSearchHit) layer.openTooltip();
  else layer.closeTooltip();
}
