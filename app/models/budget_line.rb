# == Schema Information
#
# Table name: budget_lines
#
#  id                 :bigint           not null, primary key
#  amount_cents       :bigint           default(0), not null
#  year               :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  legal_entity_id    :bigint           not null
#  team_id            :bigint
#
# Indexes
#
#  index_budget_lines_on_general_account_id  (general_account_id)
#  index_budget_lines_on_legal_entity_id     (legal_entity_id)
#  index_budget_lines_on_team_id             (team_id)
#  index_budget_lines_unique_cell            (year, legal_entity_id, COALESCE(team_id, (0)::bigint), general_account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#
# Une case du budget détaillé (étape 4 du redressement, Michael, 2026-10-18) :
# ce qu'une entité compte dépenser ou produire sur un compte, pour un pôle,
# une année civile. Toujours en positif : une charge de 1 200 € s'écrit
# 1 200, comme un produit de 1 200 €. C'est la classe du compte qui dit le
# sens.
#
# Le budget simple d'un pôle (`TeamBudget`, deux montants) s'efface dès que
# l'année a des lignes détaillées pour ce pôle : `Teams::Accounts` les lit à
# sa place.
class BudgetLine < ApplicationRecord
  has_paper_trail

  CLASSES = [6, 7].freeze

  belongs_to :legal_entity
  belongs_to :team, optional: true
  belongs_to :general_account

  validates :year, numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :general_account_id, uniqueness: { scope: %i[year legal_entity_id team_id] }
  validate :income_statement_account

  scope :for_year, ->(year) { where(year: year) }

  # { team_id => [produits, charges] } pour une année, toutes entités
  # confondues : ce que la page du pôle lit à la place de son budget simple.
  def self.team_totals(team_ids, year)
    for_year(year).where(team_id: team_ids).joins(:general_account)
                  .group(:team_id, "general_accounts.klass").sum(:amount_cents)
                  .each_with_object(Hash.new { |hash, key| hash[key] = [0, 0] }) do |((team_id, klass), cents), result|
                    result[team_id][klass == 7 ? 0 : 1] += cents
                  end
  end

  def expense? = general_account.klass == 6
  def revenue? = general_account.klass == 7

  private

  # Un budget de résultat : charges et produits. Un emprunt ou un compte de
  # banque n'y a pas sa place.
  def income_statement_account
    return if general_account.nil? || CLASSES.include?(general_account.klass)

    errors.add(:general_account, "doit être un compte de charges (classe 6) ou de produits (classe 7)")
  end
end
