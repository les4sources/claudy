# Le relief du domaine en 3D et la simulation du ruissellement.
#
# La page ne porte que des réglages : le relief lui-même (MNT LiDAR du SPW) et
# l'ortho qui le drape sont des fichiers de `storage/map-terrain/`, installés
# par `rake map:terrain:import` (voir `Maps::Terrain`), que le navigateur lit en
# binaire. Axes d'écoulement, cuvettes et pluie se calculent chez lui.
class MapReliefsController < BaseController
  # Les fichiers changent seulement quand on relance l'import : leur URL porte
  # la date du téléchargement (`?v=`), donc un an de cache sans risque.
  CACHE_CONTROL = "private, max-age=31536000, immutable".freeze

  # Les couches dont les objets se dessinent sur le relief : les lieux, la
  # gestion, l'accueil et les réseaux. Plantes, commentaires et relevés sont des
  # nuées de points qui masqueraient l'eau.
  OVERLAY_KINDS = %w[venues management welcome network].freeze

  before_action :set_terrain

  def show
    @meta = @terrain.metadata
    @version = @meta["fetched_at"].to_s
    @feature_layers = MapLayer.where(kind: OVERLAY_KINDS).ordered.map do |layer|
      { id: layer.id, kind: layer.kind, name: layer.name }
    end
  end

  def grid
    return head :not_found unless @terrain.installed?

    response.set_header("Cache-Control", CACHE_CONTROL)
    send_file @terrain.grid_path, type: "application/octet-stream", disposition: "inline"
  end

  def texture
    return head :not_found unless @terrain.texture?

    response.set_header("Cache-Control", CACHE_CONTROL)
    send_file @terrain.texture_path, type: "image/jpeg", disposition: "inline"
  end

  private

  def set_terrain
    @terrain = Maps::Terrain.current
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
    @map_view = true
  end
end
