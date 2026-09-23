# Les objets de la carte (epic #348, phase 2).
#
# Deux publics pour le même contrôleur : la carte elle-même, qui lit et écrit
# les GÉOMÉTRIES en JSON (chargement d'une couche, sommets déplacés, objet
# supprimé), et la fiche latérale, une Turbo Frame qui édite le reste (nom,
# description, consigne, photos) en Turbo Stream sans recharger la carte.
#
# Supprimer = soft-delete : un objet effacé par erreur se retrouve dans
# PaperTrail et dans la table.
class MapFeaturesController < BaseController
  PANEL_FRAME = "feature_panel".freeze

  before_action :get_feature, only: %i[show update destroy destroy_photo]

  # GET /map/features.json?layer_id=… — une `FeatureCollection` GeoJSON.
  def index
    layer = MapLayer.find(params.require(:layer_id))
    features = layer.map_features.ordered.with_attached_photos
    render json: { type: "FeatureCollection", features: features.map(&:as_geojson) }
  end

  def show
    respond_to do |format|
      format.html { render :show, layout: false }
      format.json { render json: @feature.as_geojson }
    end
  end

  # La fiche d'un objet qu'on vient de dessiner : la géométrie est posée dans
  # le champ caché par la carte, rien n'est enregistré avant « Enregistrer ».
  def new
    layer = MapLayer.find(params.require(:layer_id))
    @feature = layer.map_features.new(feature_kind: params[:feature_kind].presence || "point", geometry: {})
    render :show, layout: false
  end

  def create
    @feature = MapLayer.find(feature_params[:map_layer_id]).map_features.new(created_by: current_user)
    assign_feature
    if @feature.save
      respond_saved(:created)
    else
      respond_invalid
    end
  end

  def update
    assign_feature
    if @feature.save
      respond_saved(:ok)
    else
      respond_invalid
    end
  end

  def destroy
    @feature.soft_delete!(validate: false)
    respond_to do |format|
      format.json { head :no_content }
      # Le marqueur dit à la carte quel objet retirer : vider la fiche ne suffit
      # pas, le tracé restait dessiné.
      format.turbo_stream do
        marker = helpers.tag.div(hidden: true, data: { feature_deleted: @feature.id, layer_id: @feature.map_layer_id })
        render turbo_stream: turbo_stream.update(PANEL_FRAME, marker)
      end
      format.html { redirect_to map_path }
    end
  end

  # Retire UNE photo de la galerie.
  def destroy_photo
    @feature.photos.find(params[:photo_id]).purge_later
    @feature.reload
    render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/feature_panel", locals: { feature: @feature })
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_feature
    @feature = MapFeature.find(params[:id])
  end

  def feature_params
    params.require(:map_feature).permit(:map_layer_id, :feature_kind, :geometry, :name, :description,
                                        :management_notes, photos: [])
  end

  # Le nom et la description saisis ici sont le FRANÇAIS : les autres langues
  # arriveront avec la couche Accueil (phase 4), sans écraser celles-ci.
  def assign_feature
    attrs = feature_params
    # Une chaîne illisible reste une chaîne : la validation du modèle la refuse.
    @feature.geometry = parse_json(attrs[:geometry]) || attrs[:geometry] if attrs.key?(:geometry)
    @feature.feature_kind = attrs[:feature_kind].presence || @feature.feature_kind.presence ||
                            MapFeature.kind_for_geometry(@feature.geometry)
    @feature.name_i18n = @feature.name_i18n.to_h.merge("fr" => attrs[:name].to_s.strip) if attrs.key?(:name)
    @feature.description_i18n = @feature.description_i18n.to_h.merge("fr" => attrs[:description].to_s.strip) if attrs.key?(:description)
    if attrs.key?(:management_notes)
      @feature.properties = @feature.properties.to_h.merge("management_notes" => attrs[:management_notes].to_s.strip)
    end
    photos = Array(attrs[:photos]).compact_blank
    @feature.photos.attach(photos) if photos.any?
  end

  def parse_json(value)
    return value unless value.is_a?(String)

    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end

  def respond_saved(status)
    respond_to do |format|
      format.json { render json: @feature.as_geojson, status: status }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/feature_panel",
                                                              locals: { feature: @feature, saved: true })
      end
      format.html { redirect_to map_path }
    end
  end

  def respond_invalid
    respond_to do |format|
      format.json { render json: { errors: @feature.errors.full_messages }, status: :unprocessable_entity }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/feature_panel", locals: { feature: @feature }),
               status: :unprocessable_entity
      end
      format.html { redirect_to map_path, alert: @feature.errors.full_messages.to_sentence }
    end
  end
end
