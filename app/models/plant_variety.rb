# Une variété d'une espèce nourricière (epic #348, phase 7) : « Reinette
# Hernaut » sous « Pommier ». Le nom est unique, sans égard à la casse, au sein
# de son espèce.
class PlantVariety < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :plant_species, inverse_of: :varieties
  has_many :plants, inverse_of: :plant_variety

  before_validation { self.name = name.to_s.squish.presence }

  validates :name, presence: true,
                   uniqueness: { scope: :plant_species_id, case_sensitive: false,
                                 conditions: -> { where(deleted_at: nil) },
                                 message: "existe déjà pour cette espèce" }

  scope :ordered, -> { order(Arel.sql("lower(plant_varieties.name)")) }
  scope :named, ->(name) { where("lower(plant_varieties.name) = lower(?)", name.to_s.squish) }

  # À appeler sur les variétés d'une espèce : `species.varieties.find_or_create_by_name!("Reinette")`
  # (ou `species.find_or_create_variety!`). La portée de l'association fournit
  # l'espèce à la création.
  def self.find_or_create_by_name!(name)
    name = name.to_s.squish
    named(name).first || create!(name: name)
  rescue ActiveRecord::RecordNotUnique
    named(name).first!
  end

  def to_s = name

  # « Pommier Reinette Hernaut »
  def full_name = [plant_species&.name, name].compact.join(" ")
end
