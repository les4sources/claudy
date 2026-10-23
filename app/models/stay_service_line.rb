# Service annexe d'un séjour (Michael, 2026-10-23) : le prêt d'un set de
# disc-golf, et les autres services qu'on proposera aux groupes.
#
# Une ligne = un libellé et un montant, pour tout le séjour. On la tape à la
# main ou on la reprend d'un service du catalogue (/services), qui préremplit
# le libellé et le prix ; les deux restent modifiables, et la ligne garde ce
# qu'on a saisi même si le catalogue change ensuite. Elle s'ajoute au total du
# séjour (`Stay#recompute_aggregates!`), prix imposé compris, comme le bar.
#
# Le compte de recette est repris du service à la création : la ventilation
# d'un paiement du séjour (`Finance::VentilateStay`) range la ligne dessus.
# Sans compte, elle tombe sur la catégorie « services » de `RevenueMapping`.
# == Schema Information
#
# Table name: stay_service_lines
#
#  id                 :bigint           not null, primary key
#  amount_cents       :integer          default(0), not null
#  deleted_at         :datetime
#  label              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint
#  service_id         :bigint
#  stay_id            :bigint           not null
#
# Indexes
#
#  index_stay_service_lines_on_deleted_at          (deleted_at)
#  index_stay_service_lines_on_general_account_id  (general_account_id)
#  index_stay_service_lines_on_service_id          (service_id)
#  index_stay_service_lines_on_stay_id             (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (service_id => services.id)
#  fk_rails_...  (stay_id => stays.id)
#
class StayServiceLine < ApplicationRecord
  belongs_to :stay
  belongs_to :service, optional: true
  belongs_to :general_account, optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :amount_cents

  validates :label, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :copy_from_service, on: :create

  scope :ordered, -> { order(:created_at, :id) }

  private

  def copy_from_service
    return if service.nil?

    self.label = service.name if label.blank?
    self.general_account ||= service.general_account
  end
end
