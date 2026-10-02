# Les aménagements à l'essai de la vue 3D du relief : baissières, keylines et
# mares, dessinés sur le terrain pour voir, simulation à l'appui, ce qu'ils
# feraient de l'eau avant de creuser quoi que ce soit.
#
# Ce sont des objets de carte ordinaires, dans la couche « Aménagements à
# l'essai » (`MapLayer` kind `design`) : ils se voient aussi sur la carte 2D. Les
# cotes (largeur, profondeur, butte, pente, rayon) vivent dans
# `properties.design` ; la géométrie est le tracé (ligne) ou le contour (mare).
#
# La vue 3D lit et écrit en JSON ; supprimer = soft-delete, comme partout sur la
# carte.
class MapDesignsController < BaseController
  NUMBERS = %w[width depth berm grade radius].freeze

  def index
    features = layer.map_features.ordered.includes(:map_layer)
    render json: { type: "FeatureCollection", features: features.map(&:as_geojson) }
  end

  def create
    attrs = design_params
    type = attrs[:type].to_s
    feature = layer.map_features.new(created_by: current_user,
                                     feature_kind: type == "pond" ? "zone" : "path",
                                     geometry: parse_geometry(attrs[:geometry]))
    feature.name_i18n = { "fr" => attrs[:name].presence || default_name(type) }
    feature.properties = feature.properties.to_h.merge("design" => design_hash(type, attrs))
    if feature.save
      render json: feature.as_geojson, status: :created
    else
      render json: { errors: feature.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    layer.map_features.find(params[:id]).soft_delete!(validate: false)
    head :no_content
  end

  private

  def layer = (@layer ||= MapLayer.for_kind(:design))

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def design_params
    params.require(:design).permit(:type, :name, :geometry, *NUMBERS, center: [])
  end

  # Les cotes arrivent en chaînes (formulaire) ou en nombres (JSON) : elles
  # sont rangées en nombres, une valeur illisible restant une chaîne pour que la
  # validation du modèle la refuse.
  def design_hash(type, attrs)
    numbers = NUMBERS.each_with_object({}) do |key, hash|
      next if attrs[key].blank?

      hash[key] = Float(attrs[key], exception: false) || attrs[key]
    end
    center = Array(attrs[:center]).map { |v| Float(v, exception: false) }.compact
    { "type" => type }.merge(numbers).merge(center.size == 2 ? { "center" => center } : {})
  end

  def parse_geometry(value)
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    JSON.parse(value.to_s)
  rescue JSON::ParserError
    value
  end

  # « Mare 3 » : le numéro suit ce qui existe déjà de ce type, effacés compris
  # — un nom ne resservira pas à un autre aménagement.
  def default_name(type)
    label = MapFeature::DESIGN_TYPES.fetch(type, "Aménagement")
    count = MapFeature.unscoped.where(map_layer_id: layer.id).where("properties -> 'design' ->> 'type' = ?", type).count
    "#{label} #{count + 1}"
  end
end
