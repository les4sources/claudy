// Le statut UniFi en direct sur la couche Ethernet (epic #348, phase 10).
//
// Un nœud d'équipement UniFi (`properties.equipment === 'unifi'`) porte une
// pastille de statut dans le coin de son icône : verte en ligne, rouge hors
// ligne, grise quand on ne sait pas (pas d'équipement lié, équipement inconnu
// de l'API, clé absente, API muette). Le statut vient de `GET
// /map/unifi/devices`, relu toutes les 60 s TANT QUE la couche Ethernet est
// affichée ; masquer la couche ou quitter la page arrête la relecture.
//
// Le statut est posé sur `feature.properties.unifi_status` : `networkNodeIcon`
// le lit, si bien qu'un redessin de l'icône (sélection) garde la pastille.
// Pas d'import de `map_networks.js` (qui importe la pastille d'ici) : le
// contrôleur passe la fabrique d'icône au constructeur.

export const UNIFI_REFRESH_MS = 60_000;
export const UNIFI_STATUS_COLORS = {
  online: '#16A34A',
  offline: '#DC2626',
  unknown: '#9CA3AF',
};
const UNIFI_STATUS_LABELS = { online: 'en ligne', offline: 'hors ligne', unknown: 'statut inconnu' };

export function isUnifiNode(feature) {
  return feature?.properties?.network === 'ethernet' && feature?.properties?.equipment === 'unifi';
}

// Le statut d'un nœud d'après la réponse de l'endpoint. Tout ce qui n'est pas
// une réponse disponible ET un équipement connu en ligne/hors ligne est gris.
export function unifiStatusFor(properties, payload) {
  const id = properties?.unifi_device_id;
  if (!id || !payload?.available || !Array.isArray(payload.devices)) return 'unknown';
  const device = payload.devices.find((d) => String(d.id) === String(id));
  return device?.status === 'online' || device?.status === 'offline' ? device.status : 'unknown';
}

// La pastille, en styles en ligne : elle se pose dans le coin de l'icône
// ronde du nœud, cerclée de blanc pour se lire sur la photo aérienne.
export function unifiBadgeHtml(properties) {
  if (properties?.equipment !== 'unifi' || properties?.network !== 'ethernet') return '';
  const status = properties.unifi_status || 'unknown';
  const color = UNIFI_STATUS_COLORS[status] || UNIFI_STATUS_COLORS.unknown;
  return (
    `<span class="map-unifi-status" data-unifi-status="${status}" title="UniFi : ${UNIFI_STATUS_LABELS[status]}" ` +
    `style="position:absolute;top:-3px;right:-3px;width:10px;height:10px;border-radius:9999px;` +
    `background:${color};border:2px solid #ffffff;box-shadow:0 0 2px rgba(0,0,0,0.45)"></span>`
  );
}

// Relit les statuts toutes les 60 s tant que la couche Ethernet est visible
// et porte au moins un nœud UniFi. `sync()` est appelé après chaque
// (re)chargement de couche et chaque case cochée/décochée.
export class UnifiStatusPoller {
  // `iconFor(feature, selected)` rend l'icône Leaflet d'un nœud.
  constructor(controller, url, iconFor, interval = UNIFI_REFRESH_MS) {
    this.controller = controller;
    this.url = url;
    this.iconFor = iconFor;
    this.interval = interval;
    this.timer = null;
    this.lastPayload = null;
    this.inflight = false;
  }

  // Le groupe Leaflet de la couche Ethernet, s'il est affiché.
  visibleEthernetGroup() {
    const { controller } = this;
    if (!controller.map) return null;
    const toggle = controller.layerToggleTargets?.find((t) => t.dataset.network === 'ethernet');
    if (!toggle || !toggle.checked) return null;
    const group = controller.featureLayers?.[toggle.dataset.layerId];
    return group && controller.map.hasLayer(group) ? group : null;
  }

  unifiMarkers(group) {
    const markers = [];
    group?.eachLayer((layer) => {
      if (layer.setIcon && isUnifiNode(layer.feature)) markers.push(layer);
    });
    return markers;
  }

  sync() {
    if (!this.url) return;
    const group = this.visibleEthernetGroup();
    if (!group || this.unifiMarkers(group).length === 0) {
      this.stop();
      return;
    }
    // Une couche rechargée arrive sans statut : la dernière réponse la colore
    // tout de suite, sans attendre la prochaine relecture.
    if (this.lastPayload) this.apply(this.lastPayload);
    if (this.timer) return;
    this.timer = setInterval(() => this.refresh(), this.interval);
    this.refresh();
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async refresh() {
    // Onglet en arrière-plan : on saute ce tour, le suivant rattrapera.
    if (this.inflight || (typeof document !== 'undefined' && document.hidden)) return;
    this.inflight = true;
    try {
      const response = await fetch(this.url, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      // Session expirée, serveur en panne : les pastilles passent au gris.
      const payload = response.ok ? await response.json() : { available: false, devices: [] };
      this.lastPayload = payload;
      this.apply(payload);
    } catch (_error) {
      this.lastPayload = { available: false, devices: [] };
      this.apply(this.lastPayload);
    } finally {
      this.inflight = false;
    }
  }

  // Ne redessine que les icônes dont le statut change.
  apply(payload) {
    const group = this.visibleEthernetGroup();
    if (!group) return;
    this.unifiMarkers(group).forEach((layer) => {
      const status = unifiStatusFor(layer.feature.properties, payload);
      if (layer.feature.properties.unifi_status === status) return;
      layer.feature.properties.unifi_status = status;
      layer.setIcon(this.iconFor(layer.feature, Boolean(layer.networkSelected)));
    });
  }
}

// Dans la fiche d'un nœud Ethernet, choisir « UniFi » révèle le rappel
// « Enregistrez la fiche… » ; choisir autre chose masque le bloc UniFi.
export function handleUnifiEquipmentChange(event) {
  const select = event.target;
  if (select?.name !== 'map_feature[equipment]') return;
  const form = select.closest('form');
  if (!form) return;
  const unifi = select.value === 'unifi';
  form.querySelectorAll('[data-unifi-hint]').forEach((el) => {
    el.hidden = !unifi;
  });
  form.querySelectorAll('[data-unifi-fields]').forEach((el) => {
    el.hidden = !unifi;
  });
}
