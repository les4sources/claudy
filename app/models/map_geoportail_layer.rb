# Les couches du Géoportail de la Wallonie superposables à la carte du domaine.
#
# Rien n'est stocké chez nous : chaque couche est un service WMS du SPW
# (geoservices.wallonie.be) que Leaflet interroge directement, tuile par tuile,
# en EPSG:3857. Pas de clé, pas de proxy. La liste vit ici plutôt que dans le
# JavaScript pour que le contrôleur de carte reste générique : il lit l'URL, les
# sous-couches et l'opacité dans les `data-*` de la case à cocher.
#
# `layers` : identifiants des sous-couches WMS (voir le GetCapabilities du
# service). `z_index` : ordre d'empilement — l'ortho sous tout le reste, les
# traits fins (cadastre, courbes) au-dessus des aplats (Natura, parcellaire).
#
# `max_native_zoom` : le SPW masque certaines couches sous une échelle donnée
# (la carte des sols sous le 1:5000, les courbes sous le 1:2500). Au-delà de ce
# zoom, Leaflet redemande la tuile du zoom plafond et l'agrandit, au lieu d’une
# tuile vide.
MapGeoportailLayer = Data.define(:key, :name, :service, :layers, :opacity, :z_index, :max_native_zoom) do
  def initialize(max_native_zoom: nil, **) = super
end

class MapGeoportailLayer
  BASE_URL = "https://geoservices.wallonie.be/arcgis/services".freeze

  ALL = [
    new(key: "ortho_2026", name: "Ortho printemps 2026",
        service: "IMAGERIE/ORTHO_2026_PRINTEMPS", layers: "0", opacity: 1.0, z_index: 2),
    # 0 = trame des planches, sans intérêt à l'échelle du domaine ; 3 = tuile vide
    # sous le 1:5000.
    new(key: "sols", name: "Carte des sols",
        service: "SOL_SOUS_SOL/CNSW", layers: "1,2", opacity: 1.0, z_index: 10, max_native_zoom: 16),
    # Unités de gestion (1-7) et périmètres des sites (9-10).
    new(key: "natura2000", name: "Natura 2000",
        service: "FAUNE_FLORE/NATURA2000", layers: "1,2,3,4,5,6,7,9,10", opacity: 0.55, z_index: 11),
    # Dernière situation SIGEC : parcelles déclarées (4) et éléments du paysage —
    # haies, arbres isolés, mares (1-3).
    new(key: "parcellaire_agricole", name: "Parcellaire agricole",
        service: "AGRICULTURE/SIGEC_PARC_AGRI_LAST", layers: "1,2,3,4", opacity: 0.6, z_index: 12),
    new(key: "cadastre", name: "Plan cadastral",
        service: "PLAN_REGLEMENT/CADMAP_PARCELLES", layers: "0", opacity: 1.0, z_index: 13),
    # Courbes IGN à 1,25 m d'équidistance.
    new(key: "courbes", name: "Courbes de niveau",
        service: "IGN/CONTOURLINES", layers: "0,1,2", opacity: 0.9, z_index: 14, max_native_zoom: 17),
  ].freeze

  def self.all = ALL

  def url
    "#{BASE_URL}/#{service}/MapServer/WMSServer"
  end
end
