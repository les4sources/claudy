# == Schema Information
#
# Table name: team_budgets
#
#  id            :bigint           not null, primary key
#  expense_cents :bigint           default(0), not null
#  notes         :text
#  revenue_cents :bigint           default(0), not null
#  year          :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  team_id       :bigint           not null
#
# Indexes
#
#  index_team_budgets_on_team_id           (team_id)
#  index_team_budgets_on_team_id_and_year  (team_id,year) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id)
#
# Le budget d'un pôle pour une année civile (Michael, 2026-10-18) : ce qu'il
# compte produire, ce qu'il compte dépenser. Toutes entités confondues, comme
# le réel de la page du pôle, qui lit les écritures portant son `team_id`.
class TeamBudget < ApplicationRecord
  has_paper_trail

  belongs_to :team

  validates :year, numericality: { only_integer: true, greater_than: 2000, less_than: 2100 }
  validates :year, uniqueness: { scope: :team_id }
  validates :revenue_cents, :expense_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :amounts_are_readable

  def net_cents = revenue_cents - expense_cents

  # Les montants en euros pour le formulaire : on saisit « 12 000 », pas
  # 1200000. Une case vide vaut zéro (un service support ne produit rien).
  %i[revenue expense].each do |field|
    define_method(field) { public_send(:"#{field}_cents") / 100.0 }

    define_method(:"#{field}=") do |value|
      cents = Liability.parse_euros(value)
      (@unreadable ||= []) << field if cents.nil? && value.to_s.strip.present?
      public_send(:"#{field}_cents=", cents || 0)
    end
  end

  private

  # « 12k » ne doit pas devenir zéro en silence.
  def amounts_are_readable
    Array(@unreadable).uniq.each do |field|
      errors.add(field, "n'est pas un montant lisible (exemple : 12 000 ou 1 250,50)")
    end
  end
end
