# La carte du jour (epic #348, phase 3) : les gîtes et salles tracés sur la
# carte, colorés selon leur occupation au jour choisi, et le panneau du groupe
# présent quand on clique dessus.
#
# LECTURE SEULE. Aucune action ici ne modifie un séjour, une réservation ou un
# booking : la carte montre, la fiche séjour édite.
class MapVenuesController < BaseController
  PANEL_FRAME = MapFeaturesController::PANEL_FRAME

  before_action :set_date, only: %i[occupancy show]

  # GET /map/occupancy.json?date=AAAA-MM-JJ — { date, states: { id => { state, label } } }
  def occupancy
    render json: { date: @date.iso8601, states: Maps::DayOccupancy.new(@date).states }
  end

  # GET /map/venues/:id?date=… — le panneau du groupe présent, dans la Turbo
  # Frame de la fiche.
  def show
    @feature = MapFeature.find(params[:id])
    @venue = @feature.linked
    @occupancy = Maps::DayOccupancy.new(@date)
    render :show, layout: false
  end

  # GET /map/venues/todo — les gîtes et salles pas encore tracés, rechargés
  # par la carte après chaque enregistrement.
  def todo
    render partial: "maps/venues_todo",
           locals: { lodgings: Maps::Venues.untraced_lodgings, spaces: Maps::Venues.untraced_spaces }
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  # Une date illisible retombe sur aujourd'hui plutôt qu'en erreur : c'est un
  # paramètre d'URL qu'on partage et qu'on retape à la main.
  def set_date
    @date = Date.iso8601(params[:date].to_s)
  rescue Date::Error
    @date = Date.current
  end
end
