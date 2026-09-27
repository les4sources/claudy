# Une plante nourricière du domaine (epic #348, phase 7) : « Pommier Reinette
# Hernaut cl », son dossier (espèce, variété, zone, état), ses notes datées, ses
# photos, ses tâches et son calendrier de récolte.
#
# PLACÉE, elle a un point sur la carte : un `MapFeature` de `feature_kind`
# `plant` dans la couche Plantes (`place!`). Sans lui (`map_feature_id` nul),
# elle est « à placer » — c'est le cas de toutes les plantes importées de Notion
# (phase 8). Le statut est une donnée métier distincte : une plante « Existante »
# dans Notion peut très bien ne pas encore être placée.
#
# Les listes fermées suivent la base Notion source (libellés compris) : l'import
# de la phase 8 doit les reprendre sans perte.
class Plant < ApplicationRecord
  include HasMapPhotos

  STATUSES = {
    "existing" => "Existante",
    "to_confirm" => "À confirmer",
    "to_place" => "À placer",
    "on_plan" => "Sur plan",
    "awaiting_planting" => "En attente de plantation",
    "planted" => "Plantée",
    "dead" => "Morte",
    "to_move" => "À déplacer",
    "wild" => "Flore sauvage"
  }.freeze
  HEALTHS = { "healthy" => "Saine", "worrying" => "Inquiétante", "sick" => "Malade" }.freeze
  PRODUCTIONS = { "high" => "Élevée", "medium" => "Moyenne", "low" => "Faible", "none" => "Ne produit pas" }.freeze
  # Le port d'un fruitier : haute, moyenne ou basse tige.
  HABITS = { "standard" => "Haute tige", "half_standard" => "Moyenne tige", "dwarf" => "Basse tige" }.freeze
  # La strate. Clés anglaises stables, libellés de la base Notion.
  STRATA = {
    "tree" => "Arbre",
    "coppice" => "Arbre en cépée",
    "pollard" => "Arbre trogné",
    "food_pollard" => "Trogne alimentaire",
    "espalier" => "Palissé",
    "shrub" => "Arbuste",
    "subshrub" => "Arbrisseau",
    "herbaceous" => "Herbacée",
    "climber" => "Grimpante",
    "groundcover" => "Couvre-sol",
    "vine" => "Liane",
    "aquatic" => "Aquatique"
  }.freeze
  # Surtout pour la flore sauvage : combien d'individus.
  POPULATIONS = {
    "strong" => "Forte population",
    "medium" => "Moyenne",
    "rare" => "Rare",
    "single" => "Un seul individu"
  }.freeze
  # Le conditionnement à l'achat.
  STOCK_TYPES = {
    "container" => "Conteneur",
    "bare_root" => "Racines nues",
    "b2b" => "B2B",
    "forest_plug" => "Mini-motte forestière"
  }.freeze
  # Une plante morte ne se récolte plus : `harvestable_in` et `harvest_calendar`
  # l'écartent d'office.
  DEAD = "dead".freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  # Optionnel : nil = à placer.
  belongs_to :map_feature, optional: true, inverse_of: :plant
  belongs_to :plant_species, optional: true, inverse_of: :plants
  belongs_to :plant_variety, optional: true, inverse_of: :plants
  belongs_to :created_by, class_name: "User", optional: true
  # Pas de `dependent:` (modèle soft-deleté) : une plante supprimée garde ses
  # fenêtres, tâches et notes ; les listes les écartent (`with_live_subject`).
  has_many :harvest_windows, -> { ordered }, class_name: "PlantHarvestWindow", as: :owner, inverse_of: :owner
  has_many :map_tasks, as: :subject, inverse_of: :subject
  has_many :notes, -> { recent_first }, class_name: "MapNote", as: :subject, inverse_of: :subject

  before_validation :normalize
  before_validation :derive_species_from_variety
  before_validation :default_name
  after_update :sync_map_feature_name, if: -> { saved_change_to_name? && map_feature }
  # Une plante supprimée emporte son point : pas de marqueur orphelin.
  after_soft_delete { map_feature&.soft_delete!(validate: false) }

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :health, inclusion: { in: HEALTHS.keys }, allow_nil: true
  validates :production, inclusion: { in: PRODUCTIONS.keys }, allow_nil: true
  validates :habit, inclusion: { in: HABITS.keys }, allow_nil: true
  validates :stratum, inclusion: { in: STRATA.keys }, allow_nil: true
  validates :population, inclusion: { in: POPULATIONS.keys }, allow_nil: true
  validates :stock_type, inclusion: { in: STOCK_TYPES.keys }, allow_nil: true
  validates :number, numericality: { greater_than: 0 }, allow_nil: true,
                     uniqueness: { conditions: -> { where(deleted_at: nil) }, message: "est déjà pris par une autre plante" }
  validates :plant_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :purchase_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :planted_year, numericality: { only_integer: true, greater_than: 1800 }, allow_nil: true
  validate :variety_belongs_to_species
  validate :map_feature_is_a_plant_point

  scope :ordered, -> { order(Arel.sql("plants.number ASC NULLS LAST, lower(plants.name) ASC, plants.id ASC")) }
  scope :placed, -> { where.not(map_feature_id: nil) }
  scope :to_place, -> { where(map_feature_id: nil) }
  scope :alive, -> { where.not(status: DEAD) }
  scope :in_zone, ->(zone) { zone.blank? ? all : where(zone: zone) }
  # Un statut ou une liste de statuts ; les valeurs inconnues sont ignorées, et
  # aucun statut connu ne filtre rien.
  scope :with_status, lambda { |statuses|
    known = Array(statuses).map(&:to_s) & STATUSES.keys
    known.empty? ? all : where(status: known)
  }
  # Nom, numéro (« 42 », « #42 », « 9.1 »), espèce, nom latin, variété. Le
  # numéro se compare en nombre : 12 est stocké « 12.0 » dans la colonne décimale.
  scope :search, lambda { |query|
    query = query.to_s.squish
    if query.blank?
      all
    else
      number = BigDecimal(query.delete_prefix("#"), exception: false)
      left_joins(:plant_species, :plant_variety).where(
        "plants.name ILIKE :q OR plant_species.name ILIKE :q OR plant_species.latin_name ILIKE :q " \
        "OR plant_varieties.name ILIKE :q OR plants.number = :number",
        q: "%#{sanitize_sql_like(query)}%", number: number
      )
    end
  }

  # Les plantes vivantes qui se récoltent ce mois-là (et pour cette partie, si
  # elle est donnée), EN SQL : par leurs fenêtres propres, ou — seulement si
  # elles n'en ont aucune — par celles de leur espèce vivante. Une plante morte
  # est toujours écartée.
  def self.harvestable_in(month, part: nil)
    part = part.to_s.presence
    part = nil unless PlantHarvestWindow::PARTS.key?(part)
    window = lambda do |owner_type|
      scope = PlantHarvestWindow.where(owner_type: owner_type).in_month(month)
      part ? scope.where(part: part) : scope
    end

    own = window.call("Plant").select(:owner_id)
    inherited = PlantSpecies.where(id: window.call("PlantSpecies").select(:owner_id)).select(:id)
    without_own_windows = PlantHarvestWindow.where(owner_type: "Plant").where("plant_harvest_windows.owner_id = plants.id")

    alive.where(id: own).or(
      alive.where(plant_species_id: inherited).where.not(without_own_windows.arel.exists)
    )
  end

  # Le calendrier des récoltes (`/map/recoltes`) : { mois => [[plante, fenêtre], …] }
  # pour les douze mois, sur la portée courante (`Plant.in_zone("Verger").harvest_calendar`).
  # Même règle d'héritage que `harvestable_in` ; plantes mortes écartées.
  def self.harvest_calendar(part: nil)
    plants = alive.includes(:harvest_windows, plant_species: :harvest_windows).to_a
    MapTask::MONTHS.index_with do |month|
      plants.flat_map do |plant|
        plant.harvest_windows_effective
             .select { |window| window.includes_month?(month) && (part.blank? || window.part == part.to_s) }
             .map { |window| [plant, window] }
      end
    end
  end

  # Les zones connues, pour les filtres (« Verger », « Potager »…).
  def self.zones = where.not(zone: [nil, ""]).distinct.order(:zone).pluck(:zone)

  def status_label = STATUSES.fetch(status, status)
  def health_label = HEALTHS[health]
  def production_label = PRODUCTIONS[production]
  def habit_label = HABITS[habit]
  def stratum_label = STRATA[stratum]
  def population_label = POPULATIONS[population]
  def stock_type_label = STOCK_TYPES[stock_type]

  def dead? = status == DEAD

  # Le nom propre, sinon « Pommier Reinette Hernaut ».
  def display_name = name.presence || species_and_variety_name

  def species_and_variety_name = [plant_species&.name, plant_variety&.name].compact_blank.join(" ").presence

  # « 12 », « 9.1 » : le numéro tel qu'on l'écrit, sans « 12.0 ».
  def number_label = number&.to_s("F")&.delete_suffix(".0")

  # Les fenêtres propres de la plante si elle en a au moins une, sinon celles de
  # son espèce. Surcharger une partie, c'est donc surcharger tout le calendrier :
  # la fiche copie les fenêtres de l'espèce avant d'en modifier une.
  def harvest_windows_effective
    own = harvest_windows.to_a
    return own if own.any? || plant_species.nil?

    plant_species.harvest_windows.to_a
  end

  # « hérité de l'espèce » : la plante n'a pas de fenêtre propre et son espèce en a.
  def harvest_windows_inherited?
    harvest_windows.to_a.empty? && plant_species.present? && plant_species.harvest_windows.to_a.any?
  end

  # Les mois où il y a quelque chose à récolter, toutes parties confondues.
  def harvest_months = harvest_windows_effective.flat_map(&:months).uniq.sort

  def placed? = map_feature_id.present? && map_feature.present?

  # GeoJSON dit [longitude, latitude].
  def latitude = point_coordinates&.dig(1)
  def longitude = point_coordinates&.dig(0)

  # Pose la plante sur la carte, ou la déplace : un point de `feature_kind`
  # `plant` dans la couche Plantes, qui porte le nom de la plante. Une plante
  # « à placer » devient « existante ». Des coordonnées illisibles lèvent
  # `ActiveRecord::RecordInvalid` (géométrie du point), sans rien écrire.
  def place!(latitude:, longitude:, user: nil)
    layer = MapLayer.for_kind(:plants)
    coordinates = [Float(longitude, exception: false), Float(latitude, exception: false)]

    transaction do
      feature = map_feature || MapFeature.new(map_layer: layer, feature_kind: "plant", created_by: user)
      feature.geometry = { "type" => "Point", "coordinates" => coordinates }
      feature.name_i18n = feature.name_i18n.to_h.merge("fr" => display_name)
      feature.save!

      self.map_feature = feature
      self.status = "existing" if status == "to_place"
      save!
    end
    self
  end

  # Retire la plante de la carte : son point est soft-deleté, elle redevient
  # « à placer ». On détache AVANT de supprimer le point, pour que
  # `MapFeature#release_plant` n'ait plus rien à faire.
  def unplace!
    feature = map_feature
    transaction do
      update!(map_feature: nil, status: "to_place")
      feature&.soft_delete!(validate: false)
    end
    self
  end

  private

  def point_coordinates
    geometry = map_feature&.geometry
    geometry["coordinates"] if geometry.is_a?(Hash) && geometry["type"] == "Point"
  end

  def normalize
    self.name = name.to_s.squish.presence
    self.zone = zone.to_s.squish.presence
    %i[health production habit stratum population stock_type nursery notion_url].each do |attribute|
      self[attribute] = self[attribute].presence
    end
    self.planted_year ||= planted_on.year if planted_on
  end

  # La variété suffit : l'espèce s'en déduit.
  def derive_species_from_variety
    self.plant_species = plant_variety.plant_species if plant_variety && plant_species_id.nil?
  end

  # « Pommier Reinette Hernaut » quand on ne donne que l'espèce et la variété.
  def default_name
    self.name ||= species_and_variety_name
  end

  def variety_belongs_to_species
    return unless plant_variety && plant_variety.plant_species_id != plant_species_id

    errors.add(:plant_variety, "n'est pas une variété de #{plant_species&.name || 'cette espèce'}")
  end

  def map_feature_is_a_plant_point
    return unless map_feature

    errors.add(:map_feature, "doit être un point de plante") unless map_feature.plant_point? && map_feature.geometry_type == "Point"
  end

  def sync_map_feature_name
    map_feature.update!(name_i18n: map_feature.name_i18n.to_h.merge("fr" => name))
  end
end
