# Un objet de la carte du domaine (epic #348, phase 2) : une zone, un accès, un
# point — et, aux phases suivantes, une plante, un nœud de réseau, un
# commentaire. Le modèle est commun, la couche dit à quoi il sert.
#
# La géométrie est du GeoJSON (`Point`, `LineString`, `Polygon`) stocké tel
# quel en jsonb (décision 12). Le nom et la description sont traduits en
# données (`{fr, en, nl}`, décision 4) avec repli sur le français : seuls les
# objets vus par les hôtes (couche Accueil, phase 4) auront besoin des trois.
class MapFeature < ApplicationRecord
  FEATURE_KINDS = %w[zone path point plant node line comment observation lodging space].freeze
  GEOMETRY_TYPES = %w[Point LineString Polygon].freeze
  LOCALES = %w[fr en nl].freeze
  # Ce qu'un objet de la carte peut représenter (phase 3). Liste fermée : le
  # type polymorphe vient d'un formulaire, il ne doit jamais désigner autre
  # chose qu'un gîte ou une salle.
  LINKABLE_TYPES = { "Lodging" => "lodging", "Space" => "space" }.freeze
  # La couche Accueil (phase 4) : ce que la carte papier disait aux hôtes. Une
  # zone est publique, privée ou accessible sur demande ; un point utile porte
  # une icône prise dans une liste courte. Les libellés sont ceux de l'admin, en
  # français ; ceux des hôtes vivent dans `public.*.yml`.
  ACCESS_LEVELS = {
    "public" => "Publique",
    "private" => "Privée",
    "on_request" => "Accessible sur demande"
  }.freeze
  # Les couleurs des légendes. MÊMES valeurs que `ACCESS_COLORS` dans
  # `app/frontend/utils/map_welcome.js`, qui peint les zones : les changer des
  # deux côtés à la fois.
  ACCESS_COLORS = {
    "public" => "#2E7D4F",
    "private" => "#B42318",
    "on_request" => "#D98E04"
  }.freeze
  # Le gîte du séjour, surligné sur la page publique : `ember` du thème, la
  # couleur de l'occupé sur la carte du jour.
  STAY_LODGING_COLOR = "#C97B3D".freeze
  WELCOME_ICONS = {
    "parking" => "Parking",
    "trash" => "Poubelles",
    "wood" => "Bois",
    "oven" => "Four à bois",
    "grocery" => "Épicerie",
    "disc_golf" => "Disc-golf",
    "meeting_point" => "Point de rendez-vous",
    "animals" => "Animaux",
    "toilets" => "Toilettes",
    "water" => "Eau potable",
    "info" => "Information"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  # L'ancien lien unique vers un gîte ou une salle, remplacé par
  # `map_feature_venues` (issue #370). Colonnes conservées en base jusqu'à une
  # migration de suppression séparée ; le code ne les lit ni ne les écrit plus.
  self.ignored_columns += %w[linked_type linked_id]

  belongs_to :map_layer
  belongs_to :created_by, class_name: "User", optional: true
  # Les gîtes et salles que ce tracé représente (issue #370) : souvent un seul,
  # parfois plusieurs superposés (la Chevêche et la Hulotte). Pas de
  # `dependent:` — un tracé est soft-deleté, et c'est `release_venues` qui
  # efface alors ses liaisons.
  has_many :map_feature_venues, inverse_of: :map_feature, autosave: true
  # Le plan de travail de l'objet (phase 6). Pas de `dependent:` non plus : un
  # objet supprimé garde ses tâches en base, le carnet les écarte en ne lisant
  # que les tâches d'un porteur vivant (`MapTask.with_live_subject`).
  has_many :map_tasks, as: :subject, inverse_of: :subject
  # Les notes datées de l'objet (phase 7), la plus récente d'abord.
  has_many :map_notes, -> { recent_first }, as: :subject, inverse_of: :subject
  # La plante que ce point représente (phase 7, `feature_kind` `plant`). Pas de
  # `dependent:` (piège connu de soft_deletion sur un has_one) : c'est
  # `release_plant` qui rend la plante « à placer » quand le point disparaît.
  has_one :plant, inverse_of: :map_feature

  # Miniature, aperçu et refus clair des formats illisibles : `HasMapPhotos`,
  # partagé avec les plantes.
  include HasMapPhotos

  validates :feature_kind, inclusion: { in: FEATURE_KINDS }
  validate :geometry_is_valid_geojson
  validate :venues_traced_once
  validate :welcome_properties_are_known

  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_geometry
  after_soft_delete :release_venues
  after_soft_delete :release_plant

  # La géométrie dit le type d'objet quand on ne l'a pas précisé : un polygone
  # est une zone, une ligne un accès, un point un point.
  def self.kind_for_geometry(geometry)
    case geometry.is_a?(Hash) && geometry["type"]
    when "Polygon" then "zone"
    when "LineString" then "path"
    else "point"
    end
  end

  def name(locale = I18n.locale) = translated(name_i18n, locale)
  def description(locale = I18n.locale) = translated(description_i18n, locale)

  def geometry_type = geometry.is_a?(Hash) ? geometry["type"] : nil

  def management_notes = properties.to_h["management_notes"]

  # Couche Accueil (phase 4).
  def access = properties.to_h["access"]
  def icon = properties.to_h["icon"]

  # Les langues des hôtes où le nom ou la description existent en français mais
  # pas encore dans la langue : c'est l'indicateur discret de la fiche. Le
  # français, lui, est la langue de repli — il n'est jamais « à traduire ».
  def missing_translations
    (LOCALES - ["fr"]).select do |locale|
      [name_i18n, description_i18n].any? { |values| values.to_h["fr"].present? && values.to_h[locale].blank? }
    end
  end

  # Ce qu'un HÔTE voit d'un objet d'accueil, dans sa langue : la géométrie, le
  # nom, la description, la nature de la zone ou l'icône du point. Rien d'autre
  # — ni consigne, ni photo, ni identifiant d'un autre modèle.
  def as_public_geojson(locale = I18n.locale)
    {
      type: "Feature",
      geometry: geometry,
      properties: { name: name(locale), description: description(locale), access: access, icon: icon }.compact
    }
  end

  # Les liaisons retenues, en tenant compte d'un formulaire pas encore
  # enregistré (liaisons décochées marquées pour suppression).
  def live_venue_links = map_feature_venues.reject(&:marked_for_destruction?)

  # ["Lodging:3", "Space:5"] : les cases cochées de la fiche.
  def venue_keys = live_venue_links.map(&:key)

  # Le setter ne constantize rien — un type hors de `LINKABLE_TYPES` ou un
  # identifiant illisible est ignoré, jamais résolu. Tout décocher donne un
  # tracé sans lieu.
  def venue_keys=(values)
    wanted = Array(values).filter_map do |value|
      type, id = value.to_s.split(":", 2)
      [type, id.to_i] if LINKABLE_TYPES.key?(type) && id.to_s.match?(/\A\d+\z/)
    end.uniq

    map_feature_venues.each do |link|
      link.mark_for_destruction unless wanted.include?([link.venue_type, link.venue_id])
    end
    kept = live_venue_links.map { |link| [link.venue_type, link.venue_id] }
    (wanted - kept).each { |type, id| map_feature_venues.build(venue_type: type, venue_id: id) }

    self.feature_kind =
      if wanted.any? { |type, _| type == "Lodging" } then "lodging"
      elsif wanted.any? then "space"
      elsif venue? then MapFeature.kind_for_geometry(geometry)
      else feature_kind
      end
  end

  # Les gîtes puis les salles, chacun par nom.
  def venues
    live_venue_links.filter_map(&:venue).sort_by { |venue| [LINKABLE_TYPES.keys.index(venue.class.name), venue.name.to_s] }
  end

  # « La Chevêche · La Hulotte » : le nom d'un tracé qui n'en a pas en propre.
  def venue_names = venues.map(&:name).join(" · ")

  # Le point d'une plante sans nom propre porte celui de la plante. La plante
  # n'est lue que pour un point `plant` : `as_geojson` appelle ceci pour chaque
  # objet de la carte.
  def display_name
    name(:fr).presence || venue_names.presence || (plant&.display_name if plant_point?)
  end

  def plant_point? = feature_kind == "plant"

  def venue? = LINKABLE_TYPES.value?(feature_kind)

  # Un objet de la carte dans une `FeatureCollection` GeoJSON : la géométrie,
  # et ce dont la carte a besoin pour le dessiner et l'étiqueter.
  def as_geojson
    {
      type: "Feature",
      id: id,
      geometry: geometry,
      properties: {
        id: id,
        feature_kind: feature_kind,
        name: display_name,
        layer_id: map_layer_id,
        venue_keys: venue_keys,
        photos_count: photos.size,
        properties: properties
      }
    }
  end

  private

  def translated(values, locale)
    values = values.to_h
    values[locale.to_s].presence || values["fr"].presence
  end

  # Le formulaire envoie la géométrie comme une chaîne JSON (champ caché mis à
  # jour par Geoman) : on la parse ici pour que la validation voie un Hash.
  def normalize_geometry
    return unless geometry.is_a?(String)

    self.geometry = JSON.parse(geometry)
  rescue JSON::ParserError
    self.geometry = { "invalid" => geometry }
  end

  def geometry_is_valid_geojson
    return errors.add(:geometry, "est obligatoire") if geometry.blank?
    return errors.add(:geometry, "n'est pas un GeoJSON valide") unless geometry.is_a?(Hash)

    type = geometry["type"]
    coords = geometry["coordinates"]
    valid =
      case type
      when "Point" then position?(coords)
      when "LineString" then coords.is_a?(Array) && coords.size >= 2 && coords.all? { |c| position?(c) }
      when "Polygon" then coords.is_a?(Array) && coords.any? && coords.all? { |ring| linear_ring?(ring) }
      else false
      end

    errors.add(:geometry, "doit être un Point, une LineString ou un Polygon GeoJSON valide") unless valid
  end

  def position?(value)
    value.is_a?(Array) && value.size.between?(2, 3) && value.all? { |n| n.is_a?(Numeric) } &&
      value[0].between?(-180, 180) && value[1].between?(-90, 90)
  end

  # Un anneau GeoJSON : au moins quatre positions, la dernière égale à la
  # première.
  def linear_ring?(ring)
    ring.is_a?(Array) && ring.size >= 4 && ring.all? { |c| position?(c) } && ring.first == ring.last
  end

  # Un gîte ou une salle n'a qu'un tracé vivant : deux tracés afficheraient
  # deux fois son occupation, et le panneau ne saurait pas lequel ouvrir.
  # L'index unique en base est le dernier rempart ; ceci est le message clair.
  def venues_traced_once
    live_venue_links.select(&:new_record?).each do |link|
      taken = MapFeatureVenue.where(venue_type: link.venue_type, venue_id: link.venue_id)
      taken = taken.where.not(map_feature_id: id) if persisted?
      next unless taken.exists?

      errors.add(:base, "#{link.venue&.name || link.key} a déjà son tracé sur la carte")
    end
  end

  # Un tracé supprimé libère ses lieux : ils redeviennent « à tracer » et
  # peuvent être reliés à un nouveau tracé.
  def release_venues
    map_feature_venues.destroy_all
  end

  # Un point de plante supprimé depuis la carte rend sa plante « à placer »,
  # plutôt que de la laisser pointer vers un objet disparu. Sans validation : la
  # suppression du point ne doit pas buter sur une fiche plante incomplète.
  def release_plant
    Plant.where(map_feature_id: id).find_each do |plant|
      plant.map_feature = nil
      plant.status = "to_place"
      plant.save!(validate: false)
    end
  end

  # Une nature de zone ou une icône inconnue casserait la légende des hôtes :
  # la carte ne saurait pas de quelle couleur la peindre. Et un objet d'accueil
  # sans nom français n'a rien à dire à un hôte : le français est la langue de
  # repli de toutes les autres.
  def welcome_properties_are_known
    errors.add(:base, "Le type de zone « #{access} » est inconnu") if access.present? && !ACCESS_LEVELS.key?(access)
    errors.add(:base, "L'icône « #{icon} » est inconnue") if icon.present? && !WELCOME_ICONS.key?(icon)
    errors.add(:base, "Un objet de la couche Accueil doit avoir un nom en français") if map_layer&.welcome? && name_i18n.to_h["fr"].blank?
  end
end
