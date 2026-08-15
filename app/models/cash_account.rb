# Un compte où l'argent se pose vraiment : banque, caisse, Stripe.
#
# La distinction avec `MemberAccount` est le socle de la règle anti-double-compte
# du lot : un compte sourcier dit ce qu'on DOIT, un compte de trésorerie dit ce
# qu'on A. Une recette n'entre au journal qu'une fois, quand l'argent touche un
# compte de trésorerie.
# == Schema Information
#
# Table name: cash_accounts
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  deleted_at         :datetime
#  iban               :string
#  kind               :string           not null
#  name               :string           not null
#  stripe_account_key :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint           not null
#  legal_entity_id    :bigint           not null
#
# Indexes
#
#  index_cash_accounts_on_deleted_at          (deleted_at)
#  index_cash_accounts_on_general_account_id  (general_account_id)
#  index_cash_accounts_on_legal_entity_id     (legal_entity_id)
#  index_cash_accounts_on_name                (name) UNIQUE
#  index_cash_accounts_on_stripe_account_key  (stripe_account_key) UNIQUE WHERE (stripe_account_key IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#
class CashAccount < ApplicationRecord
  KINDS = %w[bank cash stripe].freeze
  KIND_LABELS = { "bank" => "Banque", "cash" => "Caisse", "stripe" => "Stripe" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :cash_entries, dependent: :restrict_with_error

  belongs_to :legal_entity
  belongs_to :general_account

  validates :name, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }

  def kind_label = KIND_LABELS.fetch(kind, kind)
end
