# La carte du domaine (epic #348, phase 1).
#
# 15 hectares dont tout ce qu'on sait vit ailleurs : une carte papier, une
# orthophoto chez un tiers, une base Notion, et la mémoire des gens. Cette page
# est l'endroit où tout ça se rassemble : le fond de carte (phase 1), puis les
# couches typées et leurs objets (phase 2 : la Gestion), phase après phase.
class MapsController < BaseController
  def show
    @base_layers = MapBaseLayer.ordered.to_a
    @base_layer = MapBaseLayer.find_by(id: params[:base_layer_id]) || MapBaseLayer.default_layer
    # La couche Gestion existe toujours (phase 2) : c'est le premier mode
    # d'édition. Les autres couches uniques naîtront avec leur phase.
    MapLayer.for_kind(:management)
    @layers = MapLayer.ordered.to_a
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
    @map_view = true
  end
end
