# Un axe analytique — la réponse à « pour quel pôle ».
#
# Le plan est COURT et il n'existe nulle part de `default_analytic_account_id` :
# le défaut de Winbooks, c'est un code appliqué en silence et une recette
# hébergement qui atterrit sur le bar. Ici, une écriture sans analytique reste
# visible comme non affectée, ce qui est infiniment préférable à une écriture
# mal affectée sans que personne ne le sache.
# == Schema Information
#
# Table name: analytic_accounts
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  code       :string           not null
#  deleted_at :datetime
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint
#
# Indexes
#
#  index_analytic_accounts_on_code        (code) UNIQUE
#  index_analytic_accounts_on_deleted_at  (deleted_at)
#  index_analytic_accounts_on_team_id     (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id)
#
class AnalyticAccount < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :team, optional: true
  has_many :journal_lines, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :ordered, -> { order(:code) }
  scope :actives, -> { where(active: true) }

  def to_s = "#{code} #{name}"
end
