# == Schema Information
#
# Table name: households
#
#  id           :bigint           not null, primary key
#  deleted_at   :datetime
#  kind         :string           default("resident"), not null
#  moved_in_on  :date
#  moved_out_on :date
#  name         :string           not null
#  notes        :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_households_on_deleted_at  (deleted_at)
#

# Un foyer des 4 Sources (issue #155).
#
# `resident` = habite le lieu, `member` = membre du collectif qui n'y vit pas.
# La composition n'est pas un compteur figé : elle se déduit toujours des
# périodes de présence de ses membres, pour que recalculer un mois passé donne
# le même résultat qu'à l'époque.
class Household < ApplicationRecord
  KINDS = %w[resident member].freeze

  KIND_LABELS = {
    "resident" => "Habitant",
    "member"   => "Membre du collectif"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :household_members, dependent: :destroy
  has_many :member_accounts, dependent: :restrict_with_error

  accepts_nested_attributes_for :household_members,
                                allow_destroy: true,
                                reject_if: ->(attrs) { attrs["name"].blank? }

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :moved_out_after_moved_in

  scope :ordered, -> { order(:name) }

  def kind_label = KIND_LABELS.fetch(kind, kind)

  # Membres dont la période de présence couvre `date`.
  def members_on(date)
    household_members.active_on(date)
  end

  def adults_on(date) = members_on(date).where(kind: "adult").count

  def children_on(date) = members_on(date).where(kind: "child").count

  private

  def moved_out_after_moved_in
    return if moved_out_on.blank? || moved_in_on.blank?
    return if moved_out_on >= moved_in_on

    errors.add(:moved_out_on, "doit être postérieure à la date d'arrivée")
  end
end
