# La recherche de la carte (epic #348, phase 14) : quels objets de la couche du
# mode actif répondent à une saisie — et, en mode Plantes, à des filtres.
#
# Côté serveur pour tous les modes, plutôt que sur les données déjà chargées par
# la carte : ce qu'on cherche ne vit pas toujours dans le GeoJSON (libellé des
# tâches, corps des messages d'un fil, espèce et variété d'une plante, client
# présent au jour choisi). Le résultat est une liste d'identifiants de
# `MapFeature` VIVANTS de la couche du mode, que la carte allume.
#
# Décision 10 : chaque mode cherche dans SES champs, jamais de recherche globale.
#
# La comparaison est un ILIKE (casse ignorée). Les accents, eux, comptent :
# l'extension `unaccent` n'est pas installée, « Cheveche » ne trouve pas « la
# Chevêche » — sauf pour le nom du client présent, comparé en Ruby translittéré.
module Maps
  class Search
    MODES = %w[management plants network comments biodiversity venues welcome].freeze
    PLANT_FILTERS = %w[health status stratum zone harvest_month task_month].freeze

    # Un nom ou une description traduits (`{fr, en, nl}`) : une langue suffit.
    I18N_MATCH = "EXISTS (SELECT 1 FROM jsonb_each_text(map_features.%<column>s) AS t(locale, value) " \
                 "WHERE t.value ILIKE :q)".freeze

    attr_reader :mode, :query

    def self.supported?(mode) = MODES.include?(mode.to_s)

    # `filters` : les filtres du mode Plantes (ignorés ailleurs). `layer_id` :
    # la couche réseau active — les trois réseaux partagent le mode `network`.
    def initialize(mode:, query: nil, filters: {}, date: Date.current, layer_id: nil)
      @mode = mode.to_s
      raise ArgumentError, "#{mode} n'est pas un mode de recherche" unless self.class.supported?(@mode)

      @query = query.to_s.squish
      @filters = filters.to_h.stringify_keys.slice(*PLANT_FILTERS).transform_values { |value| value.to_s.strip }
                        .compact_blank
      @date = date
      @layer_id = layer_id
    end

    # Rien à chercher (ni texte, ni filtre du mode) : aucun résultat, la carte
    # reste telle quelle.
    def criteria? = query.present? || (mode == "plants" && @filters.any?)

    def feature_ids
      return [] unless criteria?

      send(:"#{mode}_scope").ordered.pluck(:id)
    end

    private

    def like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

    # Les objets vivants (default_scope) des couches vivantes du mode.
    def base
      layers = MapLayer.where(kind: mode)
      layers = layers.where(id: @layer_id) if mode == "network" && @layer_id.present?
      MapFeature.where(map_layer_id: layers.select(:id))
    end

    def i18n_match(column) = format(I18N_MATCH, column: column)

    def management_scope
      tasks = MapTask.where(subject_type: "MapFeature").where("map_tasks.label ILIKE ?", like).select(:subject_id)
      base.where("#{i18n_match(:name_i18n)} OR map_features.properties->>'management_notes' ILIKE :q", q: like)
          .or(base.where(id: tasks))
    end

    def welcome_scope
      base.where("#{i18n_match(:name_i18n)} OR #{i18n_match(:description_i18n)}", q: like)
    end

    def biodiversity_scope
      base.where("map_features.properties->>'species_common' ILIKE :q OR map_features.properties->>'species_latin' ILIKE :q",
                 q: like)
    end

    # Le corps de n'importe quel message vivant du fil, racine ou réponse.
    def comments_scope
      base.where(id: MapComment.where("map_comments.body ILIKE ?", like).select(:map_feature_id))
    end

    # Le nom, la consigne, et le type de nœud par sa clé ou son libellé
    # (« vanne » trouve les nœuds `valve`).
    def network_scope
      needle = fold(query)
      node_types = MapLayer::NODE_TYPES.values.flat_map do |types|
        types.select { |key, label| fold(key).include?(needle) || fold(label).include?(needle) }.keys
      end.uniq
      base.where("#{i18n_match(:name_i18n)} OR map_features.properties->>'instructions' ILIKE :q " \
                 "OR map_features.properties->>'node_type' IN (:node_types)",
                 q: like, node_types: node_types.presence || [""])
    end

    # Le nom du tracé, du gîte ou de la salle qu'il représente, et le nom du
    # client présent ce jour-là (`Maps::DayOccupancy`, statut confirmé seul).
    def venues_scope
      venue_ids = Lodging.where("lodgings.name ILIKE ?", like).map { |lodging| ["Lodging", lodging.id] } +
                  Space.where("spaces.name ILIKE ?", like).map { |space| ["Space", space.id] }
      by_venue = MapFeatureVenue.where(venue_type: "Lodging", venue_id: venue_ids.filter_map { |t, id| id if t == "Lodging" })
                                .or(MapFeatureVenue.where(venue_type: "Space", venue_id: venue_ids.filter_map { |t, id| id if t == "Space" }))
                                .select(:map_feature_id)

      base.where(i18n_match(:name_i18n), q: like).or(base.where(id: by_venue)).or(base.where(id: present_customer_feature_ids))
    end

    # Une requête par lieu tracé (une vingtaine au domaine) : acceptable pour
    # une recherche tapée, et c'est la même lecture que la fiche du lieu.
    def present_customer_feature_ids
      needle = fold(query)
      day = Maps::DayOccupancy.new(@date)
      links = MapFeatureVenue.where(map_feature_id: base.select(:id)).includes(:venue)
      links.select do |link|
        venue = link.venue
        next false unless venue

        groups = link.venue_type == "Lodging" ? day.lodging_groups(venue) : day.space_groups(venue)
        groups.any? { |group| fold(group.stay&.customer&.name).include?(needle) }
      end.map(&:map_feature_id).uniq
    end

    # Les plantes PLACÉES qui répondent au texte (via `Plant.search`, plus la
    # zone) et à tous les filtres donnés.
    def plants_scope
      plants = Plant.placed
      if query.present?
        ids = Plant.search(query).pluck(:id) | Plant.where("plants.zone ILIKE ?", like).pluck(:id)
        plants = plants.where(id: ids)
      end
      plants = apply_plant_filters(plants)
      base.where(id: plants.select(:map_feature_id))
    end

    def apply_plant_filters(plants)
      f = @filters
      plants = plants.where(health: f["health"]) if Plant::HEALTHS.key?(f["health"])
      plants = plants.where(status: f["status"]) if Plant::STATUSES.key?(f["status"])
      plants = plants.where(stratum: f["stratum"]) if Plant::STRATA.key?(f["stratum"])
      plants = plants.in_zone(f["zone"]) if f["zone"].present?
      if (month = month_filter("harvest_month"))
        plants = plants.where(id: Plant.harvestable_in(month).select(:id))
      end
      if (month = month_filter("task_month"))
        tasks = MapTask.in_month(month)
        plants = plants.where(id: tasks.where(subject_type: "Plant").select(:subject_id))
                       .or(plants.where(map_feature_id: tasks.where(subject_type: "MapFeature").select(:subject_id)))
      end
      plants
    end

    def month_filter(key)
      month = Integer(@filters[key].to_s, exception: false)
      month if MapTask::MONTHS.include?(month)
    end

    def fold(text) = I18n.transliterate(text.to_s).downcase
  end
end
