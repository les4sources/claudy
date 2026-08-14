# == Schema Information
#
# Table name: teams
#
#  id            :bigint           not null, primary key
#  analytic_code :string
#  deleted_at    :datetime
#  description   :text
#  kind          :string
#  name          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  parent_id     :bigint
#
# Indexes
#
#  index_teams_on_analytic_code  (analytic_code) UNIQUE
#  index_teams_on_parent_id      (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_id => teams.id)
#
class Team < ApplicationRecord
  # Deux niveaux, pas trois : des pôles analytiques fins regroupés sous des
  # pôles économiques et des services support. La maille fine est celle où le
  # travail se fait ; la maille large est celle où la gouvernance arbitre. Les
  # confondre force à choisir entre un budget illisible et un pilotage grossier.
  #
  # Le classement réel des pôles appartient au collectif : les pôles existants
  # restent volontairement non classés tant que Michael n'a pas tranché.
  KINDS = %w[analytic economic support].freeze
  KIND_LABELS = {
    "analytic" => "Pôle analytique",
    "economic" => "Pôle économique",
    "support" => "Service support"
  }.freeze

  has_many :bundles
  has_many :tasks, through: :bundles
  has_many :team_memberships, dependent: :destroy
  has_many :humans, through: :team_memberships
  has_many :analytic_accounts, dependent: :nullify
  has_many :children, class_name: "Team", foreign_key: :parent_id, dependent: :nullify

  belongs_to :parent, class_name: "Team", optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  validates :name,
            presence: true,
            uniqueness: true
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
  validates :analytic_code, uniqueness: true, allow_nil: true
  validate :depth_of_two

  scope :roots, -> { where(parent_id: nil) }
  scope :analytics, -> { where(kind: "analytic") }

  def kind_label = kind.present? ? KIND_LABELS.fetch(kind, kind) : nil
  def referents = team_memberships.referents.includes(:human).map(&:human)

  private

  # Un parent ne peut pas avoir de parent. La hiérarchie s'arrête à deux niveaux
  # parce qu'une profondeur libre finit toujours par produire des agrégats qui
  # dépendent du chemin plutôt que du pôle.
  def depth_of_two
    return if parent.blank?

    errors.add(:parent, "est lui-même rattaché à un pôle — la hiérarchie s'arrête à deux niveaux") if parent.parent_id.present?
    errors.add(:parent, "ne peut pas être le pôle lui-même") if parent_id == id
  end
end
