# Un fond de carte daté du domaine (epic #348, phase 1).
#
# Les fonds sont VERSIONNÉS PAR DATE (décision 11) : le vol de 2027 s'ajoutera
# comme nouvelle couche par défaut, celui de 2023 restera consultable. Rien ne
# s'écrase, rien ne se remplace.
#
# Les tuiles vivent sous `storage/map-tiles/<key>/{rgb,dem}/{z}/{x}/{y}.png`,
# hors du dépôt (décision 13) : 120 Mo de binaires dans un dépôt public n'y ont
# pas leur place, et `storage/` est le dossier qui survit aux déploiements.
class MapBaseLayer < ApplicationRecord
  KINDS = %w[rgb dem].freeze

  has_paper_trail

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  # Une clé sert de segment de chemin vers `storage/map-tiles/` : tout ce qui
  # n'est pas une lettre, un chiffre, un tiret ou un souligné est refusé ICI,
  # avant même que le contrôleur de tuiles n'ait à s'en méfier.
  validates :key, format: { with: /\A[a-z0-9][a-z0-9_-]*\z/,
                            message: "ne peut contenir que des minuscules, des chiffres, - et _" }

  scope :ordered, -> { order(Arel.sql("captured_on DESC NULLS LAST"), :id) }

  after_save :demote_others, if: -> { saved_change_to_attribute?(:default) && self[:default] }

  # Le fond servi quand personne n'a choisi : celui qui porte le drapeau, sinon
  # le plus récent. Jamais `nil` silencieux côté vue — l'appelant décide quoi
  # faire d'une carte sans fond.
  def self.default_layer
    find_by(default: true) || ordered.first
  end

  # `default` est un mot trop chargé pour être lu tel quel dans une vue : ces
  # deux alias disent la même chose en clair.
  def default? = self[:default]
  def relief? = has_relief

  # L'emprise dans l'ordre attendu par Leaflet : [[sud, ouest], [nord, est]].
  def leaflet_bounds
    return nil if bounds.blank?

    [[bounds["south"], bounds["west"]], [bounds["north"], bounds["east"]]]
  end

  def center
    return nil if bounds.blank?

    [(bounds["south"].to_f + bounds["north"].to_f) / 2, (bounds["west"].to_f + bounds["east"].to_f) / 2]
  end

  def tiles_root = Rails.root.join("storage", "map-tiles", key)

  private

  # Un seul fond par défaut à la fois : deux drapeaux laisseraient le choix au
  # hasard de l'ordre SQL.
  def demote_others
    self.class.where.not(id: id).where(default: true).update_all(default: false)
  end
end
