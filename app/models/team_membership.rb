# Qui appartient à quel pôle.
#
# Ça n'existait nulle part en base, et c'est le pré-requis bloquant de « la
# facture est validée par les sourciers du pôle » : sans appartenance, on ne
# sait pas à qui envoyer le lien de validation.
# == Schema Information
#
# Table name: team_memberships
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime
#  role       :string           default("member"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  human_id   :bigint           not null
#  team_id    :bigint           not null
#
# Indexes
#
#  index_team_memberships_on_deleted_at            (deleted_at)
#  index_team_memberships_on_human_id              (human_id)
#  index_team_memberships_on_team_id               (team_id)
#  index_team_memberships_on_team_id_and_human_id  (team_id,human_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (team_id => teams.id)
#
class TeamMembership < ApplicationRecord
  ROLES = %w[member referent].freeze
  ROLE_LABELS = { "member" => "Membre", "referent" => "Référent·e" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :team
  belongs_to :human

  validates :role, inclusion: { in: ROLES }
  validates :human_id, uniqueness: { scope: :team_id }

  scope :referents, -> { where(role: "referent") }

  def role_label = ROLE_LABELS.fetch(role, role)
end
