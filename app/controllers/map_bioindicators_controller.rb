# Les relevés de plantes bio-indicatrices de la carte (couche
# « Bio-indicatrices », voir `MapFeatureBioindicator`).
#
# Même création ATOMIQUE que les relevés de biodiversité : en mode
# Bio-indicatrices, toucher la carte (ou « À ma position ») ouvre la fiche d'un
# point qui n'existe pas encore (`new`, lat/lng dans l'URL) ; le point naît à
# « Enregistrer » (`create`), avec ses photos, la date du jour et les notes,
# statut « À analyser ».
#
# L'analyse n'est PAS faite ici : Claude la lit et l'écrit par l'API agent
# (`/api/v1/map_features`, `/api/v1/bioindicator_species`). Cette page ne fait
# que la montrer, et `request_analysis` en redemande une.
class MapBioindicatorsController < BaseController
  access_section :map
  PANEL_FRAME = MapFeaturesController::PANEL_FRAME
  LIST_FRAME = "map_bioindicators".freeze
  LIST_LIMIT = 500

  before_action :get_bioindicator, only: %i[update request_analysis]

  # GET /map/bioindicators — la liste filtrée du panneau de la carte.
  def index
    @filters = { status: params[:status].presence, indicator: params[:indicator].presence }
    scope = MapFeature.filter_bioindicators(**@filters)
    @total_count = scope.count
    @to_analyze_count = MapFeature.bioindicators.where("properties->>'status' = 'to_analyze'").count
    @records = scope.with_attached_photos.limit(LIST_LIMIT).to_a
    # Un filtre posé : la carte ne montre que ces relevés.
    @filtered_ids = scope.unscope(:order).pluck(:id) if @filters.values.any?
    render :index, layout: false
  end

  # GET /map/bioindicators/new?lat=…&lng=… — la fiche d'un point pas encore créé.
  def new
    @feature = build_bioindicator
    render :new, layout: false
  end

  # POST /map/bioindicators — lat, lng et bioindicator[…].
  def create
    @feature = build_bioindicator
    assign_bioindicator
    # Un relevé sans photo n'a rien à analyser.
    @feature.errors.add(:base, "Ajoutez au moins une photo des plantes.") unless @feature.photos.attached?
    if @feature.errors.none? && @feature.save
      respond_panel(:created)
    else
      respond_invalid
    end
  end

  def update
    assign_bioindicator
    if @feature.save
      respond_panel(:ok)
    else
      respond_invalid
    end
  end

  # POST /map/bioindicators/:id/request_analysis — de nouvelles photos, un
  # doute : le relevé repasse « À analyser », l'analyse précédente reste lisible.
  def request_analysis
    @feature.request_bioindicator_analysis!
    respond_panel(:ok)
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_bioindicator
    @feature = MapFeature.bioindicators.find(params[:id])
  end

  def build_bioindicator
    lat = Float(params[:lat], exception: false)
    lng = Float(params[:lng], exception: false)
    MapLayer.for_kind(:bioindicators).map_features.new(
      feature_kind: "bioindicator", created_by: current_user,
      # Illisible = nil : la validation GeoJSON du point le refuse.
      geometry: { "type" => "Point", "coordinates" => [lng, lat] },
      properties: { "observed_on" => Date.current.iso8601, "observer_id" => current_user.id, "status" => "to_analyze" }
    )
  end

  def bioindicator_params
    params.fetch(:bioindicator, {}).permit(:observed_on, :description, photos: [])
  end

  # La date va dans les `properties`, les notes dans la description (en
  # français), les photos dans la galerie commune.
  def assign_bioindicator
    attrs = bioindicator_params
    @feature.bioindicator_attributes = attrs.to_h.slice("observed_on")
    if attrs.key?(:description)
      @feature.description_i18n = @feature.description_i18n.to_h.merge("fr" => attrs[:description].to_s.strip)
    end
    photos = Array(attrs[:photos]).compact_blank
    @feature.photos.attach(photos) if photos.any?
  end

  def respond_panel(status)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/bioindicator_panel",
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
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/bioindicator_panel",
                                                              locals: { feature: @feature }),
               status: :unprocessable_content
      end
      format.json { render json: { errors: @feature.errors.full_messages }, status: :unprocessable_content }
      format.html { redirect_to map_path, alert: @feature.errors.full_messages.to_sentence }
    end
  end
end
