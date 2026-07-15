# == Schema Information
#
# Table name: payments
#
#  booking_id                 :bigint           not null
#  payment_method             :string
#  status                     :string
#  deleted_at                 :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  amount_cents               :integer          default(0), not null
#  stripe_checkout_session_id :string
#  stripe_payment_intent_id   :string
#  id                         :uuid             not null, primary key
#
class Payment < ApplicationRecord
  # notify ActiveRecord that the default sort order should be created_at
  self.implicit_order_column = :created_at

  # Stay-first (issue #26, Phase 2 puis Phase 4) : le séjour est devenu l'ANCRE
  # du paiement. Le booking n'est plus obligatoire — un séjour sans hébergement
  # (camping, espaces) n'en a pas. Il reste renseigné pour tout le canal
  # historique, et la colonne `booking_id` ne sera retirée que bien plus tard.
  belongs_to :booking, optional: true
  # Phase 4 (« verrouillage ») : le stay devient OBLIGATOIRE. On retire
  # `optional: true` pour réactiver la validation de présence par défaut de
  # `belongs_to` — un Payment sans stay_id est désormais invalide. Les données
  # legacy déjà persistées sans stay ne sont pas re-validées (pas de re-save),
  # et sont rattrapées par `rake payments:backfill_stay_from_booking`.
  belongs_to :stay

  monetize :amount_cents, allow_nil: false

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :amount, numericality: { greater_than: 0.0 }
  validates :payment_method, presence: true

  scope :paid, -> { where(status: "paid") }
  scope :pending, -> { where(status: "pending") }

  def paid?
    self.status == "paid"
  end

  def pending?
    self.status == "pending"
  end
end
