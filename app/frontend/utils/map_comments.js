// Les commentaires en fil sur la carte (epic #348, phase 11).
//
// Quand la couche Commentaires est ACTIVE, toucher la carte ouvre la fiche
// d'un nouveau commentaire à cet endroit : un marqueur provisoire, et le champ
// « Premier message ». Rien n'existe en base avant « Publier » — le point et
// son premier message sont créés ensemble (`POST /map/comments`) ; fermer la
// fiche retire le marqueur provisoire, sans rien à supprimer.
//
// Chaque point est une bulle qui porte le nombre de messages du fil. Un fil
// résolu est estompé, et la case « Masquer les résolus » du panneau le retire.
//
// Ce module tient l'état du mode ; le contrôleur `map` lui prête sa carte, ses
// cibles et ses méthodes (`loadLayer`, `openPanel`, `discardPending`,
// `highlightSelection`, `showNotice`).

import L from '~/utils/leaflet_global';
import '~/stylesheets/map_comments.css';

const HIDE_RESOLVED_KEY = 'claudy.map.comments.hideResolved';

export function isCommentFeature(feature) {
  return feature?.properties?.feature_kind === 'comment';
}

// `label` remplace le nombre (le « + » du marqueur provisoire).
export function commentIcon(leaflet, feature, selected = false, label = null) {
  const props = feature?.properties || {};
  const resolved = Boolean(props.resolved);
  const size = selected ? 38 : 32;
  const classes = ['map-comment-pin'];
  if (resolved) classes.push('map-comment-pin--resolved');
  if (selected) classes.push('map-comment-pin--selected');
  const text = label ?? String(Number(props.comments_count) || 0);
  return leaflet.divIcon({
    className: `map-comment-pin-wrapper${resolved ? ' map-comment-pin-wrapper--resolved' : ''}`,
    html: `<span class="${classes.join(' ')}"><span class="map-comment-pin__count">${text}</span></span>`,
    iconSize: [size, size],
    // La pointe de la bulle désigne l'endroit commenté.
    iconAnchor: [size / 2, size],
  });
}

export function commentMarker(leaflet, feature, latlng) {
  const props = feature?.properties || {};
  const count = Number(props.comments_count) || 0;
  return leaflet.marker(latlng, {
    icon: commentIcon(leaflet, feature),
    riseOnHover: true,
    zIndexOffset: props.resolved ? -50 : 200,
    title: `${count} message${count > 1 ? 's' : ''}${props.resolved ? ' — résolu' : ''}`,
  });
}

export class CommentMode {
  constructor(controller) {
    this.c = controller;
    this.hideResolved = false;
    try {
      this.hideResolved = window.localStorage.getItem(HIDE_RESOLVED_KEY) === 'true';
    } catch (_error) {
      // Stockage indisponible (navigation privée) : le filtre part décoché.
    }
    this.applyFilter();

    // Une réponse ajoutée ou un message retiré par Turbo Stream ne remplace pas
    // la fiche : la bulle du point (son nombre) est rechargée après coup.
    this.onStreamRender = (event) => {
      const stream = event.target;
      const action = stream?.getAttribute?.('action');
      const target = stream?.getAttribute?.('target') || '';
      if (!['append', 'remove'].includes(action) || !/map_comment_\d+$/.test(target)) return;
      const render = event.detail.render;
      event.detail.render = async (element) => {
        await render(element);
        this.refresh();
      };
    };
    document.addEventListener('turbo:before-stream-render', this.onStreamRender);
  }

  destroy() {
    document.removeEventListener('turbo:before-stream-render', this.onStreamRender);
  }

  get active() {
    return this.c.activeLayerKind === 'comments';
  }

  layerId() {
    return this.c.layerNameTargets.find((button) => button.dataset.layerKind === 'comments')?.dataset.layerId;
  }

  newUrl() {
    return this.c.element.querySelector('[data-new-comment-url]')?.dataset.newCommentUrl;
  }

  onActivate(kind) {
    if (kind === 'comments') this.c.showNotice('Touchez la carte pour y laisser un commentaire.');
  }

  // En mode Commentaires, un objet d'une autre couche (une zone, un chemin)
  // touché ne s'ouvre pas : on commente l'endroit où l'on a touché.
  interceptFeatureClick(event, feature) {
    if (!this.active || isCommentFeature(feature)) return false;
    L.DomEvent.stopPropagation(event);
    this.onMapClick(event);
    return true;
  }

  onMapClick(event) {
    if (!this.active || this.c.placement?.active || !event?.latlng) return;
    const pm = this.c.map.pm;
    if (pm?.globalDrawModeEnabled?.() || pm?.globalEditModeEnabled?.() || pm?.globalRemovalModeEnabled?.()) return;
    const url = this.newUrl();
    if (!url) return;

    // Une couche masquée ne reçoit pas de commentaire à l'aveugle : on la rallume.
    const toggle = this.c.layerToggleTargets.find((t) => t.dataset.layerId === this.layerId());
    if (toggle && !toggle.checked) {
      toggle.checked = true;
      toggle.dispatchEvent(new Event('change'));
    }

    this.c.discardPending();
    this.c.selectedFeatureId = null;
    this.c.highlightSelection();
    const marker = L.marker(event.latlng, {
      icon: commentIcon(L, null, true, '+'),
      interactive: false,
      zIndexOffset: 1000,
    }).addTo(this.c.map);
    // `pendingLayer` : retiré par `discardPending` à la fermeture de la fiche
    // comme à la publication (la couche rechargée montre alors le vrai point).
    this.c.pendingLayer = marker;

    const { lat, lng } = event.latlng;
    this.c.openPanel(`${url}?lat=${lat.toFixed(7)}&lng=${lng.toFixed(7)}`);
  }

  refresh() {
    const id = this.layerId();
    if (id) this.c.loadLayer(id).then(() => this.c.highlightSelection());
  }

  // Seules les bulles dont l'état change sont redessinées.
  highlight(layer, selected) {
    if (!layer.setIcon || !isCommentFeature(layer.feature) || layer.commentSelected === selected) return;
    layer.commentSelected = selected;
    layer.setIcon(commentIcon(L, layer.feature, selected));
    layer.setZIndexOffset(selected ? 1000 : layer.feature.properties?.resolved ? -50 : 200);
  }

  toggleResolved(checked) {
    this.hideResolved = Boolean(checked);
    try {
      window.localStorage.setItem(HIDE_RESOLVED_KEY, String(this.hideResolved));
    } catch (_error) {
      // Sans stockage, le filtre vaut pour la visite en cours.
    }
    this.applyFilter();
  }

  applyFilter() {
    this.c.map?.getContainer().classList.toggle('map-comments-resolved-hidden', this.hideResolved);
    const box = this.c.element.querySelector('[data-comments-filter]');
    if (box) box.checked = this.hideResolved;
  }
}
