# Une couche typée de la carte du domaine (epic #348, phase 2, décision 1).
#
# « Tout est une couche » : gestion, accueil, plantes, réseaux, commentaires,
# dessins, biodiversité. Chacune s'allume ou s'éteint dans le panneau de
# gauche, et la couche ACTIVE est celle que la barre d'outils édite.
#
# La plupart des types n'ont qu'une couche (`MapLayer.for_kind(:management)` la
# crée à la demande) ; les réseaux (une par réseau) et les dessins (un par
# dessin) en ont plusieurs.
class MapLayer < ApplicationRecord
  # `venues` (phase 3) vient en tête : c'est la carte du jour, la vue par défaut.
  # `design` : les aménagements à l'essai dessinés sur le relief 3D (baissières,
  # keylines, mares), qu'on simule avant de creuser. `bioindicators` : les
  # relevés photo de plantes bio-indicatrices, analysés ensuite par Claude.
  KINDS = %w[venues management welcome plants network comments sketch biodiversity design bioindicators].freeze
  MULTIPLE_KINDS = %w[network sketch].freeze

  KIND_LABELS = {
    "venues" => "Hébergements et salles",
    "management" => "Gestion",
    "welcome" => "Accueil",
    "plants" => "Plantes nourricières",
    "network" => "Réseau",
    "comments" => "Commentaires",
    "sketch" => "Notes manuscrites",
    "biodiversity" => "Biodiversité",
    "design" => "Aménagements à l'essai",
    "bioindicators" => "Bio-indicatrices"
  }.freeze

  # Les réseaux (phase 9) : une couche `network` par réseau, reconnue par
  # `settings.network`. La couleur est celle des tracés et des pastilles ; la
  # même valeur par défaut vit dans `app/frontend/utils/map_networks.js`, mais
  # c'est `settings.color` qui fait foi (la carte le lit dans le JSON).
  NETWORKS = {
    "water" => { name: "Eau", color: "#2563EB" },
    "electric" => { name: "Électricité", color: "#D97706" },
    "ethernet" => { name: "Ethernet", color: "#7C3AED" },
    # Jaune comme les conduites et le grillage avertisseur du gaz.
    "gas" => { name: "Gaz", color: "#CA8A04" }
  }.freeze
  # Les types de nœud, par réseau : clés anglaises stables (elles sont en base,
  # dans `properties.node_type`, et nomment les icônes côté JS), libellés
  # français. Un compteur d'eau, électrique ou de gaz partage la clé `meter`
  # (une vanne d'eau ou de gaz, `valve`) : c'est la couche qui dit de quel
  # réseau il s'agit. Un répartiteur (`manifold`) distribue l'eau vers
  # plusieurs branches ; une vanne la coupe.
  NODE_TYPES = {
    "water" => {
      "source" => "Source", "catchment" => "Captage", "cistern" => "Citerne", "valve" => "Vanne",
      "manifold" => "Répartiteur", "meter" => "Compteur", "tap" => "Robinet", "manhole" => "Regard"
    },
    "electric" => {
      "panel" => "Tableau", "meter" => "Compteur", "outlet" => "Prise", "breaker" => "Disjoncteur",
      "lighting" => "Éclairage"
    },
    "ethernet" => {
      "switch" => "Switch", "access_point" => "Borne wifi", "wall_jack" => "Prise murale", "router" => "Routeur",
      "rack" => "Baie", "fiber_box" => "Boîtier fibre"
    },
    "gas" => {
      "tank" => "Citerne", "cylinder" => "Bouteille", "regulator" => "Détendeur", "valve" => "Vanne",
      "meter" => "Compteur", "boiler" => "Chaudière", "cooker" => "Cuisinière"
    }
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :created_by, class_name: "User", optional: true
  has_many :map_features, dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true
  validate :single_layer_per_unique_kind

  scope :ordered, -> { order(:position, :id) }

  # La couche unique d'un type, créée si elle manque. Pour les types à couches
  # multiples, il n'y a pas « la » couche : on refuse plutôt que d'en choisir
  # une au hasard.
  def self.for_kind(kind)
    kind = kind.to_s
    raise ArgumentError, "#{kind} n'est pas un type de couche" unless KINDS.include?(kind)
    raise ArgumentError, "#{kind} a plusieurs couches" if MULTIPLE_KINDS.include?(kind)

    find_by(kind: kind) || create!(kind: kind, name: KIND_LABELS.fetch(kind), position: KINDS.index(kind))
  rescue ActiveRecord::RecordNotUnique
    find_by!(kind: kind)
  end

  # Les couches réseau (phase 9), créées si elles manquent, dans l'ordre
  # de `NETWORKS`. Une couche `network` sans réseau déclaré mais portant le bon
  # nom est adoptée plutôt que doublée. Une couleur choisie à la main reste.
  def self.ensure_networks!
    existing = where(kind: "network").to_a
    NETWORKS.map do |network, spec|
      layer = existing.find { |candidate| candidate.network == network } ||
              existing.find { |candidate| candidate.network.blank? && candidate.name == spec[:name] } ||
              new(kind: "network", name: spec[:name], position: KINDS.index("network"))
      layer.settings = { "color" => spec[:color] }.merge(layer.settings.to_h.compact_blank, "network" => network)
      layer.save! if layer.new_record? || layer.changed?
      layer
    end
  end

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def network? = kind == "network"
  def network = (settings.to_h["network"].presence if network?)
  def network_color = settings.to_h["color"].presence || NETWORKS.dig(network, :color)
  def node_types = NODE_TYPES.fetch(network.to_s, {})
  def management? = kind == "management"
  def venues? = kind == "venues"
  def welcome? = kind == "welcome"
  def design? = kind == "design"

  # Les couches qu'on trace à la main avec la barre d'outils Geoman.
  def editable? = management? || venues? || welcome? || network?

  private

  def single_layer_per_unique_kind
    return if MULTIPLE_KINDS.include?(kind)

    scope = MapLayer.where(kind: kind)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:kind, "a déjà sa couche") if scope.exists?
  end
end
