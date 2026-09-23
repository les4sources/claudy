# La carte du domaine (epic #348, phase 1).
#
# 15 hectares dont tout ce qu'on sait vit ailleurs : une carte papier, une
# orthophoto chez un tiers, une base Notion, et la mémoire des gens. Cette page
# est l'endroit où tout ça se rassemble : le fond de carte (phase 1), puis les
# couches typées et leurs objets (phase 2 : la Gestion), la carte du jour
# (phase 3), phase après phase.
class MapsController < BaseController
  def show
    @base_layers = MapBaseLayer.ordered.to_a
    @base_layer = MapBaseLayer.find_by(id: params[:base_layer_id]) || MapBaseLayer.default_layer
    # Les couches des lieux (phase 3, la carte du jour) et de Gestion (phase 2)
    # existent toujours. Les autres couches uniques naîtront avec leur phase.
    MapLayer.for_kind(:venues)
    MapLayer.for_kind(:management)
    @date = parse_date(params[:date])
    @layers = MapLayer.ordered.to_a
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    Date.current
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
    @map_view = true
  end
end
