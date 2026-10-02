// L'information au clic des couches du Géoportail de Wallonie.
//
// Une couche affichée (case cochée, `data-geoportail-*` posés par
// MapGeoportailLayer) et un clic sur la carte hors de tout objet et de tout
// mode : une bulle s'ouvre à l'endroit touché, une section par couche. Chaque
// section interroge l'`identify` REST du SPW, directement depuis le navigateur
// (geoservices.wallonie.be renvoie l'en-tête CORS) : rien ne passe par Claudy.
//
// Tout ce qui vient du SPW est posé en `textContent` : c'est un tiers, pas du
// HTML de confiance. Un lien n'est gardé que s'il est en https.

const REST_URL = 'https://geoservices.wallonie.be/arcgis/rest/services';
const TIMEOUT_MS = 10000;

const LANDSCAPE = { woody: 'ligneux', grassy: 'herbacé', water: 'eau', stony: 'minéral' };

const decimal = (value, digits = 1) =>
  Number(value).toLocaleString('fr-BE', { minimumFractionDigits: digits, maximumFractionDigits: digits });

const present = (value) => value !== undefined && value !== null && String(value).trim() !== '' && value !== 'Null';

// Une entrée affichée : un texte, éventuellement une ligne secondaire et un lien.
const entry = (text, { detail, href, hrefLabel } = {}) => ({ text, detail, href, hrefLabel });

// Numéro de parcelle tel qu'il s'écrit au cadastre : radical sans zéros, bis,
// exposant, puissance (« 247X9 », « 12/2A »).
export function parcelNumber({ Radical: radical, Bis: bis, Exposant: exposant, Puissance: puissance }) {
  const trimmed = (value) => String(value ?? '').replace(/^0+/, '');
  let number = trimmed(radical);
  if (trimmed(bis)) number += `/${trimmed(bis)}`;
  if (present(exposant)) number += String(exposant).trim();
  if (trimmed(puissance)) number += trimmed(puissance);
  return number;
}

// Chaque couche lit ses résultats `identify` à sa façon. La clé est celle de
// MapGeoportailLayer.
const FORMATTERS = {
  sols(results) {
    return results.map(({ layerName, attributes: a }) => {
      if (!present(a['Sigle pédologique repris sur la carte'])) return entry(layerName);
      // Le SPW écrit « Définiton » : on cherche la clé par son début.
      const definitionKey = Object.keys(a).find((key) => key.startsWith('Défini'));
      const stones = a['Pourcentage estimé de la charge caillouteuse en surface'];
      return entry(`Sol ${a['Sigle pédologique repris sur la carte']}`, {
        detail: [
          present(a[definitionKey]) ? a[definitionKey] : null,
          present(stones) ? `Charge caillouteuse en surface : ${stones} %` : null,
        ]
          .filter(Boolean)
          .join(' · '),
        href: a['Lien vers la fiche de synthèse de la légende'],
        hrefLabel: 'Fiche du type de sol',
      });
    });
  },
  natura2000(results) {
    return results.map(({ attributes: a }) =>
      present(a.CODE_UG)
        ? entry(`${a.ET_CODE_UG_FR || a.ET_CODE_UG} — ${a.DESC_UG_FR || a.DESC_UG}`, {
            href: a.LIEN_UG,
            hrefLabel: "Fiche de l'unité de gestion",
          })
        : entry(`Site ${a.NOM_FR || a.NOM} (${a.CODE_SITE})`, { href: a.LIEN_SITE, hrefLabel: 'Fiche du site' })
    );
  },
  parcellaire_agricole(results) {
    return results.map(({ layerName, attributes: a }) => {
      if (present(a.CULT_NOM)) {
        const details = [`${decimal(a.DECLARED, 2)} ha déclarés`, `campagne ${a.CAMPAGNE}`];
        if (Number(a.ORGANIC) === 1) details.push('bio');
        return entry(a.CULT_NOM, { detail: details.join(' · ') });
      }
      const kind = LANDSCAPE[a.LANDSCAPE] || a.LANDSCAPE;
      return entry(layerName, { detail: present(kind) ? `Élément ${kind}` : undefined });
    });
  },
  cadastre(results) {
    return results.map(({ attributes: a }) =>
      entry(`Parcelle ${parcelNumber(a)}, section ${a.Section}`, {
        detail: [String(a['Nom Division'] || '').split('/')[0].trim(), a.CAPAKEY].filter(present).join(' · '),
      })
    );
  },
  courbes(results) {
    return results
      .map(({ attributes: a }) => pixelValue(a))
      .filter((value) => value !== null)
      .map((value) => entry(`Altitude ${decimal(value)} m`, { detail: 'Terrain nu, MNT LiDAR 2021-2022' }));
  },
  pentes(results) {
    return results
      .map(({ attributes: a }) => pixelValue(a))
      .filter((value) => value !== null)
      .map((value) => entry(`Pente ${decimal(value, 0)} %`, { detail: 'MNT LiDAR 2013-2014' }));
  },
  ruissellement(results) {
    return results.map(({ layerName, attributes: a }) => {
      if (present(a.NOMA)) {
        return entry([a.NOMB, titleCase(a.NOMA)].filter(present).join(' '), { detail: layerName });
      }
      if (present(a.arcid)) return entry('Axe de ruissellement concentré', { detail: "L'eau de pluie se concentre ici" });
      return entry(layerName);
    });
  },
  essences(results) {
    const labels = {
      NT_DESC: 'Niveau trophique',
      NH_DESC: 'Niveau hydrique',
      SS_DESC: 'Climat',
      AE_DESC: "Apports d'eau",
    };
    return results.flatMap(({ attributes: a }) =>
      Object.entries(labels)
        .map(([field, label]) => [label, a[`Raster.${field}`] ?? a[field]])
        .filter(([, value]) => present(value))
        .map(([label, value]) => entry(`${label} : ${value}`))
    );
  },
  forets_anciennes(results) {
    return results.map(({ layerName, attributes: a }) => {
      const age = a['Ancienneté de la forêt actuelle'];
      if (present(age)) return entry(capitalize(age), { detail: a['Classification de la forêt actuelle'] });
      const ferraris = a["Description de l'occupation du sol"];
      return present(ferraris) ? entry(capitalize(ferraris), { detail: 'Vers 1777' }) : entry(layerName);
    });
  },
  plan_secteur(results) {
    return results.map(({ layerName, attributes: a }) => {
      // Le SPW nomme la clé du lien « Lien Wallex » avec une espace finale.
      const wallexKey = Object.keys(a).find((key) => key.trim() === 'Lien Wallex');
      const text = present(a['Phrase carto juridique'])
        ? capitalize(a['Phrase carto juridique'])
        : present(a.Description)
          ? a.Description
          : layerName;
      return entry(text, {
        detail: present(a['Article CoDT']) ? `CoDT ${a['Article CoDT']}` : undefined,
        href: a[wallexKey],
        hrefLabel: 'Texte sur Wallex',
      });
    });
  },
};

// La valeur d'un pixel raster (« Stretch.Pixel Value »), ou `null` hors
// couverture.
function pixelValue(attributes) {
  const raw = attributes['Stretch.Pixel Value'];
  if (!present(raw) || raw === 'NoData') return null;
  const value = Number(String(raw).replace(',', '.'));
  return Number.isFinite(value) ? value : null;
}

const capitalize = (text) => String(text).charAt(0).toUpperCase() + String(text).slice(1);

// « BOCQ » → « Bocq », « RY-DE-VAUX » → « Ry-De-Vaux ».
const titleCase = (text) => String(text).toLowerCase().replace(/(^|[\s-])(\p{L})/gu, (_, sep, c) => sep + c.toUpperCase());

// Les résultats `identify` d'une couche, mis en entrées affichables. Plusieurs
// polygones voisins disent souvent la même chose : une entrée par contenu.
export function formatResults(key, results) {
  const format = FORMATTERS[key] || ((items) => items.map((r) => entry(r.value || r.layerName)));
  const seen = new Set();
  return format(results).filter(({ text, detail }) => {
    const id = `${text}|${detail ?? ''}`;
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

export class GeoportailInfo {
  // `controller` : le contrôleur de carte (sa carte Leaflet et son élément).
  constructor(controller, L) {
    this.c = controller;
    this.L = L;
    this.popup = null;
    this.request = null;
  }

  // Les cases cochées qui savent répondre à un clic (l'ortho, non).
  get sources() {
    return [...this.c.element.querySelectorAll('input[data-geoportail-info-service]:checked')];
  }

  // Appelé par le contrôleur quand aucun mode n'a pris le clic. Rend `true`
  // s'il a ouvert une bulle.
  onMapClick(event) {
    const sources = this.sources;
    if (sources.length === 0) return false;

    this.request?.abort();
    const request = new AbortController();
    this.request = request;

    const root = document.createElement('div');
    root.className = 'map-geoportail-info space-y-3 text-sm';
    const title = document.createElement('div');
    title.className = 'text-[0.65rem] font-semibold uppercase tracking-wide text-stone-400';
    title.textContent = 'Géoportail de Wallonie';
    root.append(title);

    const map = this.c.map;
    this.popup = this.L.popup({ maxWidth: 300, minWidth: 220, maxHeight: 340, autoPanPadding: [16, 16] })
      .setLatLng(event.latlng)
      .setContent(root)
      .openOn(map);

    sources.forEach((input) => {
      const section = document.createElement('section');
      const heading = document.createElement('div');
      heading.className = 'font-semibold text-stone-700';
      heading.textContent = input.dataset.geoportailName;
      const body = document.createElement('div');
      body.className = 'mt-0.5 text-stone-500';
      body.textContent = 'Chargement…';
      section.append(heading, body);
      root.append(section);

      this.identify(input, event.latlng, request.signal)
        .then((entries) => this.fill(body, entries))
        .catch((error) => {
          if (error.name === 'AbortError' && request.signal.aborted) return;
          body.textContent = 'Géoportail injoignable pour le moment.';
        })
        .finally(() => this.popup?.update());
    });
    return true;
  }

  async identify(input, latlng, signal) {
    const { geoportailKey: key, geoportailInfoService: service, geoportailInfoLayers: layers } = input.dataset;
    const map = this.c.map;
    const bounds = map.getBounds();
    const size = map.getSize();
    const params = new URLSearchParams({
      f: 'json',
      geometry: `${latlng.lng},${latlng.lat}`,
      geometryType: 'esriGeometryPoint',
      sr: '4326',
      layers: `all:${layers}`,
      // En pixels d'écran : de quoi attraper une courbe ou une haie au doigt.
      tolerance: key === 'courbes' ? '0' : '3',
      mapExtent: [bounds.getWest(), bounds.getSouth(), bounds.getEast(), bounds.getNorth()].join(','),
      imageDisplay: `${size.x},${size.y},96`,
      returnGeometry: 'false',
    });
    const timeout = AbortSignal.timeout(TIMEOUT_MS);
    const response = await fetch(`${REST_URL}/${service}/MapServer/identify?${params}`, {
      signal: AbortSignal.any ? AbortSignal.any([signal, timeout]) : signal,
    });
    if (!response.ok) throw new Error(`identify ${response.status}`);
    const json = await response.json();
    if (json.error) throw new Error(json.error.message);
    return formatResults(key, json.results || []);
  }

  fill(body, entries) {
    body.textContent = '';
    if (entries.length === 0) {
      body.textContent = 'Rien à cet endroit.';
      return;
    }
    const list = document.createElement('ul');
    list.className = 'space-y-1.5';
    entries.forEach(({ text, detail, href, hrefLabel }) => {
      const item = document.createElement('li');
      const main = document.createElement('div');
      main.className = 'text-stone-700';
      main.textContent = text;
      item.append(main);
      if (detail) {
        const small = document.createElement('div');
        small.className = 'text-xs text-stone-500';
        small.textContent = detail;
        item.append(small);
      }
      if (typeof href === 'string' && href.startsWith('https://')) {
        const link = document.createElement('a');
        link.className = 'text-xs text-4s-main underline';
        link.href = href;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        link.textContent = hrefLabel || 'En savoir plus';
        item.append(link);
      }
      list.append(item);
    });
    body.append(list);
  }

  destroy() {
    this.request?.abort();
    if (this.popup && this.c.map) this.c.map.closePopup(this.popup);
    this.popup = null;
  }
}
