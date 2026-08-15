# Une ligne du détail d'un versement Stripe.
#
# `payment` porte le lien vers le `Payment` Claudy quand la métadonnée
# `payment_id` est présente sur le PaymentIntent — elle l'est depuis la décision
# du 2026-07-21, ce qui rend la réconciliation exacte plutôt qu'approchée par
# montant et date.
# == Schema Information
#
# Table name: stripe_balance_transactions
#
#  id               :bigint           not null, primary key
#  category         :string
#  deleted_at       :datetime
#  description      :string
#  fee_cents        :bigint           default(0), not null
#  gross_cents      :bigint           default(0), not null
#  kind             :string           not null
#  net_cents        :bigint           default(0), not null
#  occurred_at      :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  payment_id       :uuid
#  stripe_id        :string           not null
#  stripe_payout_id :bigint           not null
#
# Indexes
#
#  index_stripe_balance_transactions_on_deleted_at        (deleted_at)
#  index_stripe_balance_transactions_on_payment_id        (payment_id)
#  index_stripe_balance_transactions_on_stripe_payout_id  (stripe_payout_id)
#  index_stripe_transactions_on_stripe_id                 (stripe_id) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (payment_id => payments.id)
#  fk_rails_...  (stripe_payout_id => stripe_payouts.id)
#
class StripeBalanceTransaction < ApplicationRecord
  # Les types réellement émis par Stripe. `payment` et `payment_refund` sont les
  # noms utilisés hors cartes (SEPA, virements) : les ranger dans « other » les
  # faisait traiter comme des FRAIS. La somme restait juste et une recette
  # devenait une charge — une erreur invisible au total.
  KINDS = %w[charge payment refund payment_refund adjustment stripe_fee payout transfer other].freeze
  REVENUE_KINDS = %w[charge payment refund payment_refund adjustment].freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :stripe_payout
  belongs_to :payment, optional: true

  monetize :gross_cents
  monetize :fee_cents
  monetize :net_cents

  validates :stripe_id, presence: true, uniqueness: true
  validates :kind, presence: true

  scope :ordered, -> { order(:occurred_at, :id) }
  scope :revenue, -> { where(kind: REVENUE_KINDS) }
  scope :costs, -> { where(kind: "stripe_fee") }

  def stay
    payment&.stay
  end
end
