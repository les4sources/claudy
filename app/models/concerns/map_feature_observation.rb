# Un relevé de biodiversité (epic #348, phase 13) : un point `observation` de la
# couche Biodiversité. Une plante vue, un animal croisé, à un endroit et un jour.
#
# Choix : pas de table ni de modèle `Observation`. Le relevé EST un
# `MapFeature` — il hérite gratuitement de la géométrie, des photos, du
# soft-delete, de PaperTrail et de la couche — et ce qu'il a en propre vit dans
# ses `properties` jsonb :
#
# - `realm` : `flora` ou `fauna` (requis) ;
# - `species_common` : le nom commun, texte libre (requis) ;
# - `species_latin` : le nom latin (facultatif) ;
# - `observed_on` : la date, ISO 8601 (aujourd'hui par défaut, jamais future) ;
# - `observer_id` : l'utilisateur qui a vu (l'auteur du point par défaut) ;
# - `count` : l'effectif, entier ≥ 1 (facultatif).
#
# Les notes sont la description de l'objet. Ce module ne valide et ne normalise
# que les points `observation` : les autres objets de la carte n'en voient rien.
# Aucune liaison externe (décision 9) : les noms d'espèces sont ceux que l'équipe
# a déjà saisis, rien n'est lu ni envoyé ailleurs.
module MapFeatureObservation
  extend ActiveSupport::Concern

  # La fonge (champignons) n'est ni flore ni faune : observations.be la compte à
  # part, et ses relevés y arrivent par l'import.
  REALMS = { "flora" => "Flore", "fauna" => "Faune", "fungi" => "Fonge" }.freeze
  OBSERVATION_KEYS = %w[realm species_common species_latin observed_on observer_id count].freeze
  # Un relevé venu d'ailleurs (observations.be) : sa source, son identifiant
  # là-bas (clé de l'import, jamais deux fois le même), le lien vers sa fiche,
  # l'observateur (qui n'a pas de compte Claudy), la précision du point (m), le
  # nombre de photos et le statut de validation là-bas.
  SOURCE_KEYS = %w[source source_id source_url observer_name accuracy photos_count validation].freeze
  SPECIES_MAX_LENGTH = 120

  included do
    before_validation :normalize_observation_properties, if: :observation_point?
    validate :observation_properties_are_valid, if: :observation_point?

    scope :observations, -> { where(feature_kind: "observation") }
    scope :observations_by_date, lambda {
      observations.order(Arel.sql("properties->>'observed_on' DESC NULLS LAST"), id: :desc)
    }
  end

  class_methods do
    # Les relevés du panneau, du plus récent au plus ancien. Un filtre vide ou
    # illisible (règne inconnu, année qui n'en est pas une) est ignoré.
    def filter_observations(realm: nil, species: nil, year: nil)
      scope = observations_by_date
      scope = scope.where("properties->>'realm' = ?", realm.to_s) if REALMS.key?(realm.to_s)
      if species.to_s.strip.present?
        scope = scope.where("lower(properties->>'species_common') = lower(?)", species.to_s.strip)
      end
      scope = scope.where("properties->>'observed_on' LIKE ?", "#{year}-%") if year.to_s.match?(/\A\d{4}\z/)
      scope
    end

    # « n espèces distinctes » : le nom commun sans tenir compte de la casse.
    def distinct_species_count(scope)
      scope.unscope(:order).distinct.count(Arel.sql("lower(properties->>'species_common')"))
    end

    # L'autocomplétion de la fiche : les noms communs déjà saisis qui contiennent
    # `query`, chacun avec le nom latin le plus souvent associé. Les noms qui
    # COMMENCENT par la saisie d'abord, puis les plus fréquents.
    def observation_species_suggestions(query, realm: nil, limit: 10)
      query = query.to_s.strip
      scope = observations
      scope = scope.where("properties->>'realm' = ?", realm.to_s) if REALMS.key?(realm.to_s)
      scope = scope.where("properties->>'species_common' ILIKE ?", "%#{sanitize_sql_like(query)}%") if query.present?
      rows = scope.pluck(Arel.sql("properties->>'species_common'"), Arel.sql("properties->>'species_latin'"),
                         Arel.sql("properties->>'realm'"))

      suggestions = rows.group_by { |common, _, _| common.to_s.strip.downcase }.filter_map do |key, group|
        next if key.blank?

        { common: most_frequent(group.map(&:first)), latin: most_frequent(group.map(&:second)),
          realm: most_frequent(group.map(&:third)), count: group.size }
      end
      prefix = query.downcase
      suggestions.sort_by { |s| [s[:common].downcase.start_with?(prefix) ? 0 : 1, -s[:count], s[:common].downcase] }
                 .first(limit)
    end

    private

    # La valeur la plus fréquente ; à égalité, la première saisie.
    def most_frequent(values)
      values = values.map { |v| v.to_s.strip }.compact_blank
      values.tally.max_by { |value, count| [count, -values.index(value)] }&.first
    end
  end

  def observation_point? = feature_kind == "observation"

  def realm = properties.to_h["realm"]
  def realm_label = REALMS[realm]
  def flora? = realm == "flora"
  def species_common = properties.to_h["species_common"]
  def species_latin = properties.to_h["species_latin"]
  def observer_id = properties.to_h["observer_id"]
  def observation_count = properties.to_h["count"]

  def observed_on
    Date.iso8601(properties.to_h["observed_on"].to_s)
  rescue Date::Error
    nil
  end

  def source_url = properties.to_h["source_url"]
  def observer_name = properties.to_h["observer_name"]
  def imported? = properties.to_h["source"].present?

  def observer
    User.find_by(id: observer_id) if observer_id.present?
  end

  # Les champs de la fiche : seules les clés d'un relevé passent, les autres
  # `properties` restent en place.
  def observation_attributes=(attrs)
    attrs = attrs.to_h.stringify_keys.slice(*OBSERVATION_KEYS)
    self.properties = properties.to_h.merge(attrs)
  end

  # Ce que la carte lit d'un relevé pour choisir la feuille ou la patte.
  def observation_geojson_properties
    return {} unless observation_point?

    { realm: realm, species: species_common, species_latin: species_latin, observed_on: properties.to_h["observed_on"],
      source: properties.to_h["source"], source_url: properties.to_h["source_url"] }.compact
  end

  private

  # Chaînes nettoyées, vides retirées ; date et observateur par défaut ; un
  # effectif entier devient un nombre. Une valeur illisible reste telle quelle :
  # la validation la refuse avec un message clair.
  def normalize_observation_properties
    props = properties.to_h.dup
    %w[realm species_common species_latin observed_on].each do |key|
      props[key] = props[key].to_s.strip.presence if props.key?(key)
    end
    props["observed_on"] ||= Date.current.iso8601
    props["observer_id"] = props["observer_id"].presence || created_by_id
    props["observer_id"] = Integer(props["observer_id"], exception: false) || props["observer_id"] if props["observer_id"]
    props["count"] = Integer(props["count"].to_s.strip, exception: false) || props["count"] if props.key?("count")
    self.properties = props.reject { |_, value| value.nil? || value == "" }
  end

  def observation_properties_are_valid
    errors.add(:base, "Un relevé est un point de la carte.") unless geometry_type == "Point"
    errors.add(:base, "Choisissez Flore, Faune ou Fonge.") unless REALMS.key?(realm)
    if (url = properties.to_h["source_url"]).present? && !url.to_s.match?(%r{\Ahttps?://\S+\z})
      errors.add(:base, "Le lien vers la source doit être une adresse web.")
    end
    if species_common.blank?
      errors.add(:base, "Indiquez l'espèce observée.")
    elsif species_common.length > SPECIES_MAX_LENGTH || species_latin.to_s.length > SPECIES_MAX_LENGTH
      errors.add(:base, "Le nom de l'espèce est trop long.")
    end
    if observed_on.nil?
      errors.add(:base, "La date d'observation est illisible.")
    elsif observed_on > Date.current
      errors.add(:base, "La date d'observation ne peut pas être dans le futur.")
    end
    count = properties.to_h["count"]
    errors.add(:base, "L'effectif est un nombre entier, au moins 1.") unless count.nil? || (count.is_a?(Integer) && count >= 1)
    if observer_id.present? && !(observer_id.is_a?(Integer) && User.exists?(observer_id))
      errors.add(:base, "Cet observateur n'existe pas.")
    end
  end
end
