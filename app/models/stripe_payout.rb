# Un versement Stripe : le NET qui arrive sur le compte bancaire.
#
# C'est l'objet qui manque pour comptabiliser une ligne bancaire Stripe sans
# « opération diverse » manuelle. La ligne fait 1 243,17 € ; le versement dit de
# quels paiements et de quels frais ce montant est la somme algébrique.
# == Schema Information
#
# Table name: stripe_payouts
#
#  id              :bigint           not null, primary key
#  account_key     :string           not null
#  amount_cents    :bigint           not null
#  arrival_date    :date
#  currency        :string           default("EUR"), not null
#  deleted_at      :datetime
#  status          :string
#  synced_at       :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  cash_account_id :bigint
#  stripe_id       :string           not null
#
# Indexes
#
#  index_stripe_payouts_on_account_and_id   (account_key,stripe_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_stripe_payouts_on_arrival_date     (arrival_date)
#  index_stripe_payouts_on_cash_account_id  (cash_account_id)
#  index_stripe_payouts_on_deleted_at       (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
#
class StripePayout < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :cash_account, optional: true
  has_many :stripe_balance_transactions, dependent: :destroy

  monetize :amount_cents

  validates :account_key, :stripe_id, presence: true
  validates :stripe_id, uniqueness: { scope: :account_key }

  scope :ordered, -> { order(arrival_date: :desc, id: :desc) }
  scope :for_account, ->(key) { where(account_key: key.to_s) }

  def account_label = StripeService.label_for(account_key)

  # Le contrôle qui vaut d'être fait : la somme des transactions doit refermer
  # le net versé. Un versement qui ne se referme pas est un versement qu'on n'a
  # pas fini de lire, pas un versement à comptabiliser.
  # La transaction de type `payout` est la contrepartie du versement lui-même,
  # pas une de ses composantes : la compter reviendrait à soustraire le
  # versement de lui-même.
  def component_transactions = stripe_balance_transactions.where.not(kind: "payout")
  def transactions_net_cents = component_transactions.sum(:net_cents)
  def balanced? = transactions_net_cents == amount_cents
  def gross_cents = component_transactions.revenue.sum(:gross_cents)
  def unbalanced_reason
    return nil if balanced?

    "transactions à #{transactions_net_cents} pour un net de #{amount_cents}"
  end

  # Les frais sont de deux natures : la commission prélevée sur chaque
  # encaissement (`fee`), et les frais facturés à part (`stripe_fee`, dont le net
  # est négatif). Les additionner en valeur positive donne le coût réel.
  def fees_cents
    component_transactions.sum(:fee_cents) - component_transactions.costs.sum(:net_cents)
  end
end
