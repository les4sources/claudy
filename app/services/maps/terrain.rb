module Maps
  # Le relief du domaine pour la vue 3D et la simulation du ruissellement.
  #
  # Une grille d'altitudes à 1 m au sol, lue dans le MNT LiDAR 2021-2022 du SPW
  # (50 cm, terrain nu), plus l'ortho du printemps 2026 exportée sur la même
  # emprise pour draper le relief. Les deux fichiers vivent sous
  # `storage/map-terrain/`, hors du dépôt comme les tuiles du fond (le dépôt est
  # public), et s'installent avec `rake map:terrain:import`.
  #
  # La grille est en EPSG:3857 : l'ortho s'exporte dans la même projection, elle
  # tombe donc pixel pour pixel sur le relief sans reprojection. Le pas en 3857
  # est `1 m / cos(latitude)` — à Yvoir, 1,56 unité de Mercator pour un mètre.
  #
  # `-surface.bin` : même grille, le modèle de SURFACE (arbres et toits
  # compris), avec son propre minimum dans `metadata["surface"]`.
  #
  # `grid.bin` : des Uint16 little-endian, ligne par ligne du nord au sud, ouest
  # vers est, en centimètres au-dessus de `z_min`. 65535 = pas de donnée.
  class Terrain
    KEY = "mnt-2021-2022".freeze
    NODATA = 65_535
    EARTH_RADIUS = 6_378_137.0

    attr_reader :root

    def self.current = new

    def initialize(root: Rails.root.join("storage", "map-terrain"))
      @root = Pathname(root)
    end

    def grid_path = root.join("#{KEY}.bin")
    def texture_path = root.join("#{KEY}-ortho.jpg")
    def surface_path = root.join("#{KEY}-surface.bin")
    def metadata_path = root.join("#{KEY}.json")

    def installed? = grid_path.file? && metadata_path.file?
    def texture? = texture_path.file?
    def surface? = surface_path.file? && metadata["surface"].present?

    # Les métadonnées telles qu'écrites par l'import ; `{}` tant que rien n'est
    # installé ou que le fichier est illisible — la page dit alors quoi faire.
    def metadata
      return {} unless metadata_path.file?

      JSON.parse(metadata_path.read)
    rescue JSON::ParserError
      {}
    end

    # WGS84 → Web Mercator, et retour. Deux formules fermées : pas de proj4 pour
    # une seule projection.
    def self.to_mercator(lat, lng)
      x = EARTH_RADIUS * lng * Math::PI / 180
      y = EARTH_RADIUS * Math.log(Math.tan(Math::PI / 4 + lat * Math::PI / 360))
      [x, y]
    end

    def self.to_wgs84(x, y)
      lng = x / EARTH_RADIUS * 180 / Math::PI
      lat = (2 * Math.atan(Math.exp(y / EARTH_RADIUS)) - Math::PI / 2) * 180 / Math::PI
      [lat, lng]
    end
  end
end
