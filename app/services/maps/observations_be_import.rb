require "net/http"

module Maps
  # Importe les observations d'un lieu d'observations.be (« Fonds d'Ahinvaux »,
  # lieu 241623) dans la couche Biodiversité de la carte.
  #
  # L'API publique d'observations.be (`/api/v1/locations/:id/observations/`) rend
  # chaque observation avec son espèce (noms en français avec `Accept-Language:
  # fr`), sa date, son effectif, son point et sa précision, son observateur et le
  # lien vers sa fiche. Aucune clé : ce sont des données publiques.
  #
  # L'import est REJOUABLE : la clé est l'identifiant observations.be
  # (`properties.source_id`). Une observation déjà importée est mise à jour, une
  # nouvelle est créée ; rien n'est supprimé (une observation retirée là-bas
  # reste ici, à effacer à la main). Les relevés saisis dans Claudy ne sont
  # jamais touchés.
  class ObservationsBeImport
    BASE_URL = "https://observations.be/api/v1".freeze
    SOURCE = "observations.be".freeze
    PAGE_SIZE = 200

    # Groupes d'espèces d'observations.be → règnes de la carte. Les plantes,
    # mousses, lichens et algues sont de la flore, les champignons de la fonge,
    # le reste de la faune ; les « perturbations » (30) ne sont pas des espèces.
    FLORA_GROUPS = [10, 12, 19].freeze
    FUNGI_GROUPS = [11].freeze
    SKIPPED_GROUPS = [30].freeze

    Result = Data.define(:created, :updated, :skipped, :errors)

    def initialize(location_id:, layer: MapLayer.for_kind(:biodiversity), http: nil, logger: nil)
      @location_id = Integer(location_id)
      @layer = layer
      @http = http || method(:get_json)
      @logger = logger
    end

    def call
      created = updated = skipped = 0
      errors = []
      each_observation do |observation|
        attrs = attributes_for(observation)
        next skipped += 1 unless attrs

        feature = existing[attrs["source_id"]] || @layer.map_features.new(feature_kind: "observation")
        was_new = feature.new_record?
        feature.geometry = observation["point"]
        feature.properties = feature.properties.to_h.merge(attrs)
        notes = observation["notes"].to_s.strip
        feature.description_i18n = feature.description_i18n.to_h.merge("fr" => notes) if notes.present?
        if feature.save
          was_new ? created += 1 : updated += 1
        else
          errors << "#{attrs['source_url']} : #{feature.errors.full_messages.to_sentence}"
        end
      end
      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    # Les champs d'un relevé de la carte, ou nil pour une observation qu'on ne
    # prend pas (sans point, sans espèce, perturbation).
    def attributes_for(observation)
      species = observation["species_detail"] || {}
      group = observation["species_group"] || species["group"]
      return nil if observation["point"].blank? || SKIPPED_GROUPS.include?(group)

      latin = species["scientific_name"].to_s.strip.presence
      common = species["name"].to_s.strip.presence || latin
      return nil if common.blank?

      count = Integer(observation["number"].to_s, exception: false)
      {
        "realm" => realm_for(group), "species_common" => common.first(MapFeatureObservation::SPECIES_MAX_LENGTH),
        "species_latin" => latin&.first(MapFeatureObservation::SPECIES_MAX_LENGTH),
        "observed_on" => observation["date"], "count" => (count if count && count >= 1),
        "source" => SOURCE, "source_id" => observation["id"].to_s,
        "source_url" => observation["permalink"].presence || "https://observations.be/observation/#{observation['id']}/",
        "observer_name" => observation.dig("user_detail", "name"), "accuracy" => observation["accuracy"],
        "photos_count" => Array(observation["photos"]).size, "validation" => observation["validation_status"]
      }.compact
    end

    private

    def realm_for(group)
      return "flora" if FLORA_GROUPS.include?(group)
      return "fungi" if FUNGI_GROUPS.include?(group)

      "fauna"
    end

    # Les relevés déjà importés de ce lieu, par identifiant observations.be.
    def existing
      @existing ||= @layer.map_features.where(feature_kind: "observation")
                          .where("properties->>'source' = ?", SOURCE)
                          .index_by { |feature| feature.properties.to_h["source_id"] }
    end

    def each_observation(&)
      url = "#{BASE_URL}/locations/#{@location_id}/observations/?limit=#{PAGE_SIZE}"
      page = 0
      while url
        body = @http.call(url)
        page += 1
        @logger&.call("page #{page} : #{Array(body['results']).size} observations")
        Array(body["results"]).each(&)
        url = body["next"]
      end
    end

    def get_json(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Accept-Language"] = "fr"
        response = http.request(request)
        raise "observations.be : HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
