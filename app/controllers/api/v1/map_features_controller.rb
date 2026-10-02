module Api
  module V1
    # Les objets de la carte du domaine (epic #348, phase 8) : zones, accès,
    # points, dans une couche. La géométrie est du GeoJSON (Point, LineString,
    # Polygon) en [longitude, latitude].
    #
    # La couche se donne par `layer_id`, ou par `layer_kind` pour les couches
    # uniques (management, welcome, plants…). Un point de PLANTE ne se crée pas
    # ici : il se pose par `POST /plants` ou `PATCH /plants/:id` (latitude,
    # longitude), pour rester lié à sa fiche.
    class MapFeaturesController < BaseController
      include MapWriting

      FEATURE_KINDS = MapFeature::FEATURE_KINDS.index_with(&:itself).freeze

      def index
        scope = MapFeature.ordered.includes(:map_layer, :plant)
        scope = scope.where(map_layer_id: params[:layer_id]) if params[:layer_id].present?
        scope = scope.joins(:map_layer).where(map_layers: { kind: params[:layer_kind] }) if params[:layer_kind].present?
        scope = scope.where(feature_kind: params[:kind].to_s.split(",")) if params[:kind].present?
        @map_features = paginate(scope)
      end

      def show
        @map_feature = find_feature(params[:id])
      end

      def create
        @map_feature = MapFeature.new
        save_feature(:created)
      end

      def update
        @map_feature = find_feature(params[:id])
        save_feature(:ok)
      end

      def destroy
        MapFeature.find(params[:id]).soft_delete!(validate: false)
        head :no_content
      end

      private

      def find_feature(id)
        MapFeature.includes(:map_layer, :plant, :map_notes, :map_tasks, photos_attachments: :blob).find(id)
      end

      def save_feature(status)
        errors = []
        attributes = feature_attributes(errors)
        return render_errors(errors) if errors.any?

        @map_feature.assign_attributes(attributes)
        @map_feature.feature_kind ||= MapFeature.kind_for_geometry(@map_feature.geometry)
        @map_feature.save!
        @map_feature = find_feature(@map_feature.id)
        render :show, status: status
      end

      def feature_attributes(errors)
        body = params.require(:map_feature)
        attributes = {}
        attributes[:geometry] = plain(body[:geometry]) if body.key?(:geometry)
        attributes[:properties] = plain(body[:properties]).presence || {} if body.key?(:properties)
        %i[name_i18n description_i18n].each do |field|
          attributes[field] = plain(body[field]).to_h.slice(*MapFeature::LOCALES) if body.key?(field)
        end
        attributes[:position] = body[:position] if body.key?(:position)

        if body.key?(:feature_kind)
          kind = closed_value("feature_kind", body[:feature_kind], FEATURE_KINDS, errors)
          if kind == "plant" && @map_feature.feature_kind != "plant"
            errors << "un point de plante se pose par POST /plants ou PATCH /plants/:id (latitude, longitude)"
          end
          attributes[:feature_kind] = kind if kind
        end

        layer = layer_param(body, errors)
        attributes[:map_layer] = layer if layer
        errors << "layer_id ou layer_kind est obligatoire" if @map_feature.new_record? && layer.nil? && errors.empty?
        attributes
      end

      def layer_param(body, errors)
        if body[:layer_id].present?
          MapLayer.find_by(id: body[:layer_id]) || (errors << "layer_id #{body[:layer_id]} : couche inconnue"; nil)
        elsif body[:layer_kind].present?
          kind = closed_value("layer_kind", body[:layer_kind], MapLayer::KIND_LABELS, errors)
          return unless kind
          return MapLayer.for_kind(kind) unless MapLayer::MULTIPLE_KINDS.include?(kind)

          errors << "layer_kind #{kind} a plusieurs couches : donner layer_id"
          nil
        end
      end

      # Paramètres → Hash/Array Ruby ordinaires, pour le jsonb. Une chaîne
      # (GeoJSON sérialisé) passe telle quelle : le modèle la parse.
      def plain(value)
        value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.to_hash : value
      end
    end
  end
end
