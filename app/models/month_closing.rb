# Un mois arrêté.
#
# L'objet est minuscule et c'est voulu : tout l'intérêt est dans ce qu'il faut
# avoir fait pour pouvoir le créer. L'état du mois ne se stocke pas — il se
# recalcule depuis les données à chaque affichage. Un état stocké se périme au
# premier mouvement qui arrive en retard, et une case cochée qui ment est pire
# que pas de case du tout.
# == Schema Information
#
# Table name: month_closings
#
#  id           :bigint           not null, primary key
#  closed_at    :datetime         not null
#  closed_by    :string
#  deleted_at   :datetime
#  notes        :text
#  period_month :date             not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_month_closings_on_deleted_at    (deleted_at)
#  index_month_closings_on_period_month  (period_month) UNIQUE WHERE (deleted_at IS NULL)
#
class MonthClosing < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  validates :period_month, presence: true, uniqueness: true
  validates :closed_at, presence: true

  before_validation :normalize_period

  scope :ordered, -> { order(period_month: :desc) }

  def self.closed?(month) = exists?(period_month: month.beginning_of_month)

  def label = I18n.l(period_month, format: "%B %Y")

  private

  def normalize_period
    self.period_month = period_month.beginning_of_month if period_month.present?
  end
end
