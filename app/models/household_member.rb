# == Schema Information
#
# Table name: household_members
#
#  id           :bigint           not null, primary key
#  born_on      :date
#  deleted_at   :datetime
#  ended_on     :date
#  kind         :string           default("adult"), not null
#  name         :string           not null
#  started_on   :date             not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  household_id :bigint           not null
#  human_id     :bigint
#
# Indexes
#
#  index_household_members_on_deleted_at                   (deleted_at)
#  index_household_members_on_household_id                 (household_id)
#  index_household_members_on_household_id_and_started_on  (household_id,started_on)
#  index_household_members_on_human_id                     (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (household_id => households.id)
#  fk_rails_...  (human_id => humans.id)
#

# Une personne rattachée à un ménage, sur une période (issue #155).
#
# `human` est FACULTATIF : un enfant ou un conjoint n'est pas forcément membre
# de l'équipe. `name` porte donc toujours le nom affichable — et il faut qu'il
# le porte, parce que `Human` a un `default_scope` sur `status: "active"` : une
# personne désactivée ferait disparaître le nom si on comptait sur l'association.
class HouseholdMember < ApplicationRecord
  KINDS = %w[adult child other].freeze

  KIND_LABELS = {
    "adult" => "Adulte",
    "child" => "Enfant",
    "other" => "Autre"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :household
  belongs_to :human, optional: true

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :started_on, presence: true
  validate :ended_after_started

  # Période inclusive des deux bornes, ouverte à droite quand `ended_on` est nul.
  scope :active_on, lambda { |date|
    where(started_on: ..date)
      .where("household_members.ended_on IS NULL OR household_members.ended_on >= ?", date)
  }

  scope :ordered, -> { order(:kind, :name) }

  def kind_label = KIND_LABELS.fetch(kind, kind)

  def active_on?(date)
    return false if started_on.blank? || date.blank?

    started_on <= date && (ended_on.nil? || ended_on >= date)
  end

  private

  def ended_after_started
    return if ended_on.blank? || started_on.blank?
    return if ended_on >= started_on

    errors.add(:ended_on, "doit être postérieure à la date d'entrée")
  end
end
