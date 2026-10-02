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
    # Les couches des lieux (phase 3, la carte du jour), de Gestion (phase 2) et
    # d'Accueil (phase 4, la carte des hôtes) existent toujours. Les autres
    # couches uniques naîtront avec leur phase.
    MapLayer.for_kind(:venues)
    MapLayer.for_kind(:management)
    MapLayer.for_kind(:welcome)
    # Les plantes nourricières (phase 7).
    MapLayer.for_kind(:plants)
    # Les réseaux (phase 9) : Eau, Électricité, Ethernet.
    MapLayer.ensure_networks!
    # Les commentaires en fil (phase 11) : active, la couche fait du clic sur la
    # carte un nouveau commentaire.
    MapLayer.for_kind(:comments)
    # La biodiversité (phase 13) : active, la couche fait du clic sur la carte
    # un nouveau relevé.
    MapLayer.for_kind(:biodiversity)
    # Les plantes bio-indicatrices : active, la couche fait du clic sur la
    # carte un nouveau relevé photo, à analyser.
    MapLayer.for_kind(:bioindicators)
    @date = parse_date(params[:date])
    @layers = MapLayer.ordered.to_a
    # `/map?feature=<id>` (phase 6, lien du carnet) : la carte s'ouvre centrée
    # sur l'objet, fiche ouverte. Seul l'id d'un objet VIVANT part vers la page ;
    # un id inconnu, supprimé ou illisible est ignoré sans erreur.
    @focus_feature_id = MapFeature.where(id: params[:feature].to_s[/\A\d+\z/]).pick(:id)
    # `/map?plant=<id>` (phase 7, liens des récoltes et de la liste) : la fiche
    # d'une plante, placée ou non, s'ouvre en arrivant.
    @focus_plant_id = Plant.where(id: params[:plant].to_s[/\A\d+\z/]).pick(:id)
    # `/map?plant=new` : la fiche « Nouvelle plante » (bouton de la liste).
    @open_new_plant = params[:plant] == "new"
    # Le compteur « À placer » du panneau ; la carte le tient ensuite à jour.
    @unplaced_count = Plant.alive.to_place.count
  end

  # GET /map/search?mode=<kind>&q=…[&layer_id=…][&date=…][&health=…&status=…
  #   &stratum=…&zone=…&harvest_month=…&task_month=…]
  # → { mode, count, feature_ids } (phase 14). Un mode inconnu est un 422 : la
  # carte n'envoie que les kinds de ses couches.
  def search
    mode = params[:mode].to_s
    unless Maps::Search.supported?(mode)
      return render json: { error: "Mode de recherche inconnu" }, status: :unprocessable_content
    end

    filters = params.slice(*Maps::Search::PLANT_FILTERS).permit(*Maps::Search::PLANT_FILTERS).to_h
    ids = Maps::Search.new(mode: mode, query: params[:q], filters: filters, date: parse_date(params[:date]),
                           layer_id: params[:layer_id].to_s[/\A\d+\z/]).feature_ids
    render json: { mode: mode, count: ids.size, feature_ids: ids }
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
