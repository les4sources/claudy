# Les couches du Géoportail de la Wallonie superposables à la carte du domaine.
#
# Rien n'est stocké chez nous : chaque couche est un service WMS du SPW
# (geoservices.wallonie.be) que Leaflet interroge directement, tuile par tuile,
# en EPSG:3857. Pas de clé, pas de proxy. La liste vit ici plutôt que dans le
# JavaScript pour que le contrôleur de carte reste générique : il lit l'URL, les
# sous-couches et l'opacité dans les `data-*` de la case à cocher.
#
# `layers` : identifiants des sous-couches WMS, lus dans le GetCapabilities du
# service. ATTENTION : le WMS d'ArcGIS ne numérote pas comme le REST (souvent à
# rebours) — `layers` suit le WMS, `info_layers` le REST. `z_index` : ordre d'empilement — les photos sous tout le reste, les
# traits fins (cadastre, courbes) au-dessus des aplats (Natura, parcellaire).
#
# `max_native_zoom` : le SPW masque certaines couches sous une échelle donnée
# (la carte des sols sous le 1:5000, les courbes sous le 1:2500). Au-delà de ce
# zoom, Leaflet redemande la tuile du zoom plafond et l'agrandit, au lieu d'une
# tuile vide.
#
# `info_service` / `info_layers` : ce qu'on interroge (identify REST, voir
# `utils/map_geoportail.js`) quand on touche la carte, couche affichée. Souvent
# le même service, sauf pour les courbes : l'altitude exacte vient du MNT
# LiDAR, pas de la courbe la plus proche. Sans `info_service` (l'ortho), la
# couche ne répond pas au clic.
MapGeoportailLayer = Data.define(:key, :name, :group, :service, :layers, :opacity, :z_index, :max_native_zoom,
                                 :info_service, :info_layers) do
  def initialize(max_native_zoom: nil, info_service: nil, info_layers: nil, **) = super
end

class MapGeoportailLayer
  BASE_URL = "https://geoservices.wallonie.be/arcgis/services".freeze

  # Les intitulés des groupes du panneau, dans l'ordre d'affichage.
  GROUPS = {
    photos: "Photos aériennes",
    terrain: "Relief, sol et eau",
    milieux: "Milieux et règles",
  }.freeze

  # Empilement : les photos (2-4) sous le relief du fond (5), puis les aplats
  # (6-12), puis les traits (13-15).
  ALL = [
    new(key: "ortho_2026", name: "Ortho printemps 2026", group: :photos,
        service: "IMAGERIE/ORTHO_2026_PRINTEMPS", layers: "0", opacity: 1.0, z_index: 4),
    new(key: "ortho_1994", name: "Ortho 1994-2000", group: :photos,
        service: "IMAGERIE/ORTHO_1994_2000", layers: "0", opacity: 1.0, z_index: 3),
    new(key: "ortho_1971", name: "Ortho 1971", group: :photos,
        service: "IMAGERIE/ORTHO_1971", layers: "0", opacity: 1.0, z_index: 2),

    # Courbes IGN à 1,25 m d'équidistance ; au clic, l'altitude du MNT 50 cm.
    new(key: "courbes", name: "Courbes de niveau", group: :terrain,
        service: "IGN/CONTOURLINES", layers: "0,1,2", opacity: 0.9, z_index: 15, max_native_zoom: 17,
        info_service: "RELIEF/WALLONIE_MNT_2021_2022", info_layers: "0"),
    # Vue en couleur du MNT LiDAR 2013-2014 (WMS 1, REST 0).
    new(key: "pentes", name: "Pentes", group: :terrain,
        service: "RELIEF/WALLONIE_MNP_2013_2014__PENTES", layers: "1", opacity: 0.55, z_index: 7,
        info_service: "RELIEF/WALLONIE_MNP_2013_2014__PENTES", info_layers: "0"),
    # Axes de ruissellement (WMS 13, REST 1), dépressions (11 / 3) et cours
    # d'eau (4-9 / 5-10). Masqués par le SPW sous le 1:1000.
    new(key: "ruissellement", name: "Ruissellement et cours d'eau", group: :terrain,
        service: "EAU/LIDAXES", layers: "13,11,9,8,7,6,5,4", opacity: 1.0, z_index: 13, max_native_zoom: 19,
        info_service: "EAU/LIDAXES", info_layers: "1,3,5,6,7,8,9,10"),
    # Séries et ravins (WMS 1-2) ; ni la trame des planches ni la tuile vide
    # « échelle inférieure au 1:5000 ».
    new(key: "sols", name: "Carte des sols", group: :terrain,
        service: "SOL_SOUS_SOL/CNSW", layers: "1,2", opacity: 1.0, z_index: 10, max_native_zoom: 16,
        info_service: "SOL_SOUS_SOL/CNSW", info_layers: "1,2"),
    # Le fichier écologique des essences : quatre rasters superposés, on en
    # montre un (niveaux hydriques, WMS 2) ; le clic lit les quatre (REST 4-7) —
    # trophique, hydrique, sous-secteur climatique, apports d'eau.
    new(key: "essences", name: "Fichier écologique des essences", group: :terrain,
        service: "FAUNE_FLORE/FEE", layers: "2", opacity: 0.55, z_index: 6,
        info_service: "FAUNE_FLORE/FEE", info_layers: "4,5,6,7"),

    # Périmètres des sites (WMS 1-2) et unités de gestion (4-10). Au clic :
    # l'unité de gestion (REST 7) et le site (REST 9).
    new(key: "natura2000", name: "Natura 2000", group: :milieux,
        service: "FAUNE_FLORE/NATURA2000", layers: "1,2,4,5,6,7,8,9,10", opacity: 0.55, z_index: 11,
        info_service: "FAUNE_FLORE/NATURA2000", info_layers: "7,9"),
    # Ancienneté des forêts actuelles (WMS 1, REST 2) et forêt de la carte de
    # Ferraris (WMS 0, REST 3).
    new(key: "forets_anciennes", name: "Forêts anciennes", group: :milieux,
        service: "FORET/FORETANC", layers: "1,0", opacity: 0.5, z_index: 9,
        info_service: "FORET/FORETANC", info_layers: "2,3"),
    # Zones d'affectation (WMS 2, REST 22), mesures et prescriptions (21-20 /
    # 4-5), périmètres de protection (10-6 / 15-19).
    new(key: "plan_secteur", name: "Plan de secteur", group: :milieux,
        service: "AMENAGEMENT_TERRITOIRE/PDS", layers: "2,21,20,10,9,8,7,6", opacity: 0.5, z_index: 8,
        info_service: "AMENAGEMENT_TERRITOIRE/PDS", info_layers: "22,4,5,15,16,17,18,19"),
    new(key: "cadastre", name: "Plan cadastral", group: :milieux,
        service: "PLAN_REGLEMENT/CADMAP_PARCELLES", layers: "0", opacity: 1.0, z_index: 14,
        info_service: "PLAN_REGLEMENT/CADMAP_PARCELLES", info_layers: "0"),
    # Dernière situation SIGEC : parcelles déclarées (WMS 2, REST 4) et éléments
    # du paysage — haies, arbres isolés, mares (WMS 4-6, REST 1-3).
    new(key: "parcellaire_agricole", name: "Parcellaire agricole", group: :milieux,
        service: "AGRICULTURE/SIGEC_PARC_AGRI_LAST", layers: "2,4,5,6", opacity: 0.6, z_index: 12,
        info_service: "AGRICULTURE/SIGEC_PARC_AGRI_LAST", info_layers: "1,2,3,4"),
  ].freeze

  def self.all = ALL

  # Les couches par groupe, dans l'ordre de GROUPS : [[intitulé, couches], …].
  def self.grouped
    GROUPS.map { |key, label| [label, ALL.select { |layer| layer.group == key }] }
  end

  def url
    "#{BASE_URL}/#{service}/MapServer/WMSServer"
  end
end
