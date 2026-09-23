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
  KINDS = %w[venues management welcome plants network comments sketch biodiversity].freeze
  MULTIPLE_KINDS = %w[network sketch].freeze

  KIND_LABELS = {
    "venues" => "Hébergements et salles",
    "management" => "Gestion",
    "welcome" => "Accueil",
    "plants" => "Plantes nourricières",
    "network" => "Réseau",
    "comments" => "Commentaires",
    "sketch" => "Notes manuscrites",
    "biodiversity" => "Biodiversité"
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

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def management? = kind == "management"
  def venues? = kind == "venues"

  # Les couches qu'on trace à la main avec la barre d'outils Geoman.
  def editable? = management? || venues?

  private

  def single_layer_per_unique_kind
    return if MULTIPLE_KINDS.include?(kind)

    scope = MapLayer.where(kind: kind)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:kind, "a déjà sa couche") if scope.exists?
  end
end
