module Api
  module V1
    # Les plantes nourricières du domaine (epic #348, phase 8) — c'est par ici
    # que les ~95 plantes de la base Notion entrent dans Claudy.
    #
    # Ce qui rend l'import simple :
    # - `species_name` / `variety_name` sont résolus (créés au besoin), en plus
    #   de `plant_species_id` / `plant_variety_id` ;
    # - les listes fermées acceptent la clé OU le libellé Notion (« Existante ») ;
    # - POST avec un `notion_url` déjà connu met la plante à jour au lieu d'en
    #   créer une seconde (`meta.created` le dit) : un import rejoué ne double rien.
    #
    # Position : `latitude` + `longitude` → `place!` (point dans la couche
    # Plantes) ; `placed: false` explicite → `unplace!` ; rien → on n'y touche pas.
    class PlantsController < BaseController
      include MapWriting

      CLOSED_LISTS = {
        status: Plant::STATUSES, health: Plant::HEALTHS, production: Plant::PRODUCTIONS,
        habit: Plant::HABITS, stratum: Plant::STRATA, population: Plant::POPULATIONS,
        stock_type: Plant::STOCK_TYPES
      }.freeze
      ATTRIBUTES = %i[name number zone status health production habit stratum population stock_type
                      plant_count purchase_price_cents planted_on planted_year altitude mature_height mature_spread nursery notion_url
                      notes plant_species_id plant_variety_id].freeze
      INCLUDES = [:plant_variety, :harvest_windows, { map_feature: [], plant_species: :harvest_windows }].freeze

      def index
        scope = Plant.ordered.includes(*INCLUDES)
                     .with_status(params[:status].to_s.split(",").presence)
                     .in_zone(params[:zone])
                     .search(params[:q])
        case params[:placed].to_s
        when "true" then scope = scope.placed
        when "false" then scope = scope.to_place
        end
        if params[:number].present?
          number = BigDecimal(params[:number].to_s.delete_prefix("#"), exception: false)
          scope = number ? scope.where(number: number) : scope.none
        end
        scope = scope.where(plant_species_id: params[:plant_species_id]) if params[:plant_species_id].present?

        @plants = paginate(scope)
      end

      def show
        @plant = find_plant(params[:id])
      end

      def create
        notion_url = params.dig(:plant, :notion_url).to_s.strip.presence
        @plant = (Plant.find_by(notion_url: notion_url) if notion_url) || Plant.new
        @created = @plant.new_record?
        save_plant(@created ? :created : :ok)
      end

      def update
        @plant = find_plant(params[:id])
        save_plant(:ok)
      end

      def destroy
        find_plant(params[:id]).soft_delete!(validate: false)
        head :no_content
      end

      private

      def find_plant(id)
        Plant.includes(*INCLUDES, :map_tasks, :map_notes, photos_attachments: :blob).find(id)
      end

      def save_plant(status)
        body = params.require(:plant)
        attributes = body.permit(*ATTRIBUTES).to_h.symbolize_keys
        errors = []
        CLOSED_LISTS.each do |field, choices|
          attributes[field] = closed_value(field, attributes[field], choices, errors) if attributes.key?(field)
        end
        attributes.delete(:status) if attributes.key?(:status) && attributes[:status].nil?
        windows = harvest_windows_param(:plant, errors)
        position = position_param(body, errors)
        errors.concat(number_errors(attributes[:number])) if attributes.key?(:number)
        return render_errors(errors) if errors.any?

        Plant.transaction do
          resolve_species!(body, attributes)
          @plant.assign_attributes(attributes)
          @plant.save!
          replace_harvest_windows!(@plant, windows)
          apply_position!(position)
        end

        @plant = find_plant(@plant.id)
        render :show, status: status
      rescue SpeciesMissing
        render_errors("variety_name demande une espèce : species_name ou plant_species_id")
      end

      class SpeciesMissing < StandardError; end

      # `species_name` et `variety_name` → identifiants, créés au besoin. Donner
      # une nouvelle espèce sans variété efface la variété d'une autre espèce.
      def resolve_species!(body, attributes)
        if body[:species_name].present?
          species = PlantSpecies.find_or_create_by_name!(body[:species_name],
                                                        **{ latin_name: body[:species_latin_name].presence }.compact)
          attributes[:plant_species_id] = species.id
        end

        # Un identifiant inconnu est un 404, pas une violation de clé étrangère.
        PlantSpecies.find(attributes[:plant_species_id]) if attributes[:plant_species_id].present?
        PlantVariety.find(attributes[:plant_variety_id]) if attributes[:plant_variety_id].present?

        species_id = attributes.fetch(:plant_species_id, @plant.plant_species_id)
        if attributes.key?(:plant_species_id) && !attributes.key?(:plant_variety_id) && body[:variety_name].blank? &&
           @plant.plant_variety && @plant.plant_variety.plant_species_id != species_id.to_i
          attributes[:plant_variety_id] = nil
        end
        return if body[:variety_name].blank?

        raise SpeciesMissing if species_id.blank?

        attributes[:plant_variety_id] = PlantSpecies.find(species_id).find_or_create_variety!(body[:variety_name]).id
      end

      # :place (avec coordonnées), :unplace, ou nil (ne rien changer).
      def position_param(body, errors)
        latitude = body[:latitude]
        longitude = body[:longitude]
        if latitude.present? || longitude.present?
          lat = Float(latitude.to_s, exception: false)
          lng = Float(longitude.to_s, exception: false)
          if lat.nil? || lng.nil? || !lat.between?(-90, 90) || !lng.between?(-180, 180)
            errors << "latitude et longitude doivent être données ensemble, en degrés décimaux (WGS84)"
            return nil
          end
          { latitude: lat, longitude: lng }
        elsif body.key?(:placed) && ActiveModel::Type::Boolean.new.cast(body[:placed]) == false
          :unplace
        end
      end

      def apply_position!(position)
        case position
        when Hash then @plant.place!(**position)
        when :unplace then @plant.unplace! if @plant.map_feature_id
        end
      end

      # Un numéro déjà pris est l'erreur la plus probable d'un import : on dit
      # par qui, pour qu'elle se corrige sans fouiller.
      def number_errors(value)
        return [] if value.blank?

        number = BigDecimal(value.to_s, exception: false)
        return ["number « #{value} » n'est pas un nombre (ex. 12 ou 9.1)"] if number.nil?

        taken = Plant.where(number: number).where.not(id: @plant.id).first
        return [] unless taken

        ["number #{taken.number_label} est déjà pris par la plante ##{taken.id} « #{taken.display_name} »"]
      end
    end
  end
end
