# Les relevés de biodiversité de la carte (epic #348, phase 13).
#
# Un relevé est un `MapFeature` `observation` de la couche Biodiversité (voir
# `MapFeatureObservation`). Création ATOMIQUE, comme les commentaires : en mode
# Biodiversité, toucher la carte (ou « À ma position ») ouvre la fiche d'un
# point qui n'existe pas encore (`new`, lat/lng dans l'URL). Le point n'est
# créé qu'à « Enregistrer » (`create`) : annuler ou fermer la fiche ne laisse
# aucun point orphelin.
#
# Une fois créé, le relevé s'ouvre au clic sur la carte par `map_features#show`
# (qui sert cette fiche pour un point `observation`) et s'enregistre ici
# (`update`). La suppression et le retrait d'une photo restent ceux de tout
# objet de la carte (`map_features#destroy`, `#destroy_photo`).
#
# `index` est la liste du panneau (Turbo Frame `map_observations`), `page` la
# même liste en page annexe, `species` l'autocomplétion de la fiche. Aucune
# liaison externe (décision 9) : on ne propose que ce que l'équipe a déjà saisi.
class MapObservationsController < BaseController
  PANEL_FRAME = MapFeaturesController::PANEL_FRAME
  LIST_FRAME = "map_observations".freeze
  LIST_LIMIT = 500

  before_action :get_observation, only: :update

  # GET /map/observations — la liste filtrée du panneau de la carte.
  def index
    load_list
    render :index, layout: false
  end

  # GET /map/biodiversite — la même liste, en page annexe.
  def page
    load_list
  end

  # GET /map/observations/new?lat=…&lng=… — la fiche d'un point pas encore créé.
  def new
    @feature = build_observation
    render :new, layout: false
  end

  # POST /map/observations — lat, lng et observation[…].
  def create
    @feature = build_observation
    assign_observation
    if @feature.save
      respond_panel(:created)
    else
      respond_invalid
    end
  end

  def update
    assign_observation
    if @feature.save
      respond_panel(:ok)
    else
      respond_invalid
    end
  end

  # GET /map/observations/species.json?q=…&realm=… — les noms communs déjà
  # saisis, avec le nom latin le plus souvent associé.
  def species
    render json: MapFeature.observation_species_suggestions(params[:q], realm: params[:realm])
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  # Seul un relevé passe par ici : un autre objet de la carte n'existe pas
  # pour ce contrôleur (404).
  def get_observation
    @feature = MapFeature.observations.find(params[:id])
  end

  def build_observation
    lat = Float(params[:lat], exception: false)
    lng = Float(params[:lng], exception: false)
    MapLayer.for_kind(:biodiversity).map_features.new(
      feature_kind: "observation", created_by: current_user,
      # Illisible = nil : la validation GeoJSON du point le refuse.
      geometry: { "type" => "Point", "coordinates" => [lng, lat] },
      properties: { "observed_on" => Date.current.iso8601, "observer_id" => current_user.id }
    )
  end

  def observation_params
    params.fetch(:observation, {}).permit(:realm, :species_common, :species_latin, :observed_on, :observer_id,
                                          :count, :description, photos: [])
  end

  # Les champs du relevé vont dans les `properties`, les notes dans la
  # description (en français), les photos dans la galerie commune.
  def assign_observation
    attrs = observation_params
    @feature.observation_attributes = attrs.to_h.slice(*MapFeatureObservation::OBSERVATION_KEYS)
    if attrs.key?(:description)
      @feature.description_i18n = @feature.description_i18n.to_h.merge("fr" => attrs[:description].to_s.strip)
    end
    photos = Array(attrs[:photos]).compact_blank
    @feature.photos.attach(photos) if photos.any?
  end

  def respond_panel(status)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/observation_panel",
                                                              locals: { feature: @feature, saved: true }),
               status: status
      end
      format.json { render json: @feature.as_geojson, status: status }
      format.html { redirect_to map_path(feature: @feature.id) }
    end
  end

  def respond_invalid
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/observation_panel",
                                                              locals: { feature: @feature }),
               status: :unprocessable_content
      end
      format.json { render json: { errors: @feature.errors.full_messages }, status: :unprocessable_content }
      format.html { redirect_to map_path, alert: @feature.errors.full_messages.to_sentence }
    end
  end

  # Filtres : règne, espèce (nom commun, sans casse), année. Les listes de
  # choix (espèces, années) portent sur TOUS les relevés, pas sur le filtre.
  def load_list
    @filters = { realm: params[:realm].presence, species: params[:species].presence, year: params[:year].presence }
    scope = MapFeature.filter_observations(**@filters)
    @species_count = MapFeature.distinct_species_count(scope)
    @total_count = scope.count
    @observations = scope.limit(LIST_LIMIT).to_a
    @observers = User.where(id: @observations.map(&:observer_id).compact.uniq).index_by(&:id)
    @years = MapFeature.observations.distinct.pluck(Arel.sql("left(properties->>'observed_on', 4)"))
                       .compact.select { |year| year.match?(/\A\d{4}\z/) }.sort.reverse
    @species_options = MapFeature.observation_species_suggestions(nil, limit: 1000).map { |s| s[:common] }
                                 .sort_by { |name| I18n.transliterate(name.downcase) }
  end
end
