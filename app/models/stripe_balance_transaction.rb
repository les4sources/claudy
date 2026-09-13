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
#  account_key      :string
#  available_on     :date
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
#  cash_account_id  :bigint
#  payment_id       :uuid
#  stripe_id        :string           not null
#  stripe_payout_id :bigint
#
# Indexes
#
#  idx_on_account_key_occurred_at_d76b62d952              (account_key,occurred_at)
#  index_stripe_balance_transactions_on_cash_account_id   (cash_account_id)
#  index_stripe_balance_transactions_on_deleted_at        (deleted_at)
#  index_stripe_balance_transactions_on_payment_id        (payment_id)
#  index_stripe_balance_transactions_on_stripe_payout_id  (stripe_payout_id)
#  index_stripe_transactions_on_stripe_id                 (stripe_id) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => cash_accounts.id)
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

  # En mode `ledger`, une transaction du solde n'appartient à aucun versement :
  # elle appartient au COMPTE (epic #250). Le versement reste obligatoire en
  # pratique pour le mode `per_payout`, mais la contrainte se dit désormais en
  # validation — « un versement OU un compte » — plutôt qu'en clé étrangère.
  belongs_to :stripe_payout, optional: true
  belongs_to :cash_account, optional: true
  belongs_to :payment, optional: true

  has_many :cash_entries, as: :source, dependent: :nullify

  monetize :gross_cents
  monetize :fee_cents
  monetize :net_cents

  validates :stripe_id, presence: true, uniqueness: true
  validates :kind, presence: true
  validate :belongs_somewhere

  scope :ordered, -> { order(:occurred_at, :id) }
  scope :revenue, -> { where(kind: REVENUE_KINDS) }
  scope :costs, -> { where(kind: "stripe_fee") }
  scope :for_account, ->(key) { where(account_key: key.to_s) }
  # Les transactions d'un compte tenu en grand livre. Le critère est le MODE du
  # compte, pas l'absence de versement : la transaction de type `payout` en
  # pointe un, et c'est justement celle qu'on veut contrôler (epic #250).
  scope :ledger, -> { where(cash_account_id: CashAccount.stripe_ledger.select(:id)) }

  def stay
    payment&.stay
  end

  def revenue? = REVENUE_KINDS.include?(kind)

  # La catégorie telle qu'elle sert de clé de correspondance : `nil` est une
  # valeur, pas un trou — « les transactions sans catégorie » se décident une
  # fois comme les autres.
  def mapping_category = category.presence

  private

  # Une transaction qui ne pointe ni un versement ni un compte est une
  # transaction que personne ne retrouvera : ni le coût d'encaissement, ni le
  # contrôle du grand livre Stripe ne sauraient où la ranger.
  def belongs_somewhere
    return if stripe_payout_id.present? || cash_account_id.present?

    errors.add(:base, "Une transaction Stripe appartient à un versement ou à un compte de trésorerie.")
  end
end
