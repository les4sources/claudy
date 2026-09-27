# Une espèce nourricière du domaine (epic #348, phase 7) : « Pommier »,
# « Néflier ». Catalogue LOCAL à Claudy (décision de Michael du 2026-09-27 :
# pas de lien Terranova).
#
# L'espèce porte les fenêtres de récolte PAR DÉFAUT : une plante sans fenêtre
# propre hérite de celles de son espèce (`Plant#harvest_windows_effective`).
# Elle tient aussi une petite fiche botanique, reprise de la base Notion.
class PlantSpecies < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :created_by, class_name: "User", optional: true
  # Pas de `dependent:` (modèle soft-deleté) : une espèce supprimée garde ses
  # variétés et ses plantes en base ; `plant.plant_species` vaut alors nil.
  has_many :varieties, -> { order(Arel.sql("lower(plant_varieties.name)")) },
           class_name: "PlantVariety", inverse_of: :plant_species
  has_many :plants, inverse_of: :plant_species
  has_many :harvest_windows, -> { ordered }, class_name: "PlantHarvestWindow", as: :owner, inverse_of: :owner

  before_validation :normalize

  validates :name, presence: true,
                   uniqueness: { case_sensitive: false, conditions: -> { where(deleted_at: nil) },
                                 message: "existe déjà dans le catalogue" }

  scope :ordered, -> { order(Arel.sql("lower(plant_species.name)")) }
  scope :named, ->(name) { where("lower(plant_species.name) = lower(?)", name.to_s.squish) }
  # L'autocomplétion de la fiche plante : le nom ou le nom latin.
  scope :search, lambda { |query|
    # Casse et accents ignorés : « neflier » propose « Néflier ».
    pattern = AccentFolding.pattern(query.to_s.squish)
    query.blank? ? all : where("#{AccentFolding.sql('plant_species.name')} LIKE :q " \
                               "OR #{AccentFolding.sql('plant_species.latin_name')} LIKE :q", q: pattern)
  }

  # « créer “Néflier” » depuis la fiche : l'espèce existante, quelle que soit la
  # casse, ou une nouvelle. Deux créations simultanées se rejoignent grâce à
  # l'index unique.
  def self.find_or_create_by_name!(name, **attributes)
    name = name.to_s.squish
    named(name).first || create!(attributes.merge(name: name))
  rescue ActiveRecord::RecordNotUnique
    named(name).first!
  end

  def to_s = name

  # « Pommier (Malus domestica) »
  def full_name = latin_name.present? ? "#{name} (#{latin_name})" : name

  def find_or_create_variety!(name) = varieties.find_or_create_by_name!(name)

  private

  def normalize
    self.name = name.to_s.squish.presence
    self.latin_name = latin_name.to_s.squish.presence
    self.exposure = Array(exposure).map { |value| value.to_s.squish }.compact_blank.uniq
    self.edible_parts = Array(edible_parts).map { |value| value.to_s.squish }.compact_blank.uniq
  end
end
