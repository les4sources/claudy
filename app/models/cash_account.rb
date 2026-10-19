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
#  stripe_mode        :string           default("per_payout"), not null
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

  # Deux façons de lire un compte Stripe (epic #250, décision 1).
  #
  # `per_payout` — versements AUTOMATIQUES : Stripe sait quelles ventes un
  # versement couvre, et on lit le compte versement par versement. C'est le
  # comportement de l'issue #187, celui du compte Claudy, et il ne bouge pas.
  #
  # `ledger` — versements MANUELS : Stripe refuse le filtre par versement, parce
  # que le montant viré est choisi librement et ne correspond à aucune liste de
  # ventes. On tient alors le solde Stripe comme un vrai compte de trésorerie :
  # chaque transaction y devient une ligne, et le versement devient un virement
  # interne vers la banque. La règle B2 tient — la recette entre au journal quand
  # l'argent touche un compte de trésorerie, et le solde Stripe en est un.
  STRIPE_MODES = %w[per_payout ledger].freeze
  STRIPE_MODE_LABELS = {
    "per_payout" => "Par versement (versements automatiques)",
    "ledger" => "Grand livre (versements manuels)"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :cash_entries, dependent: :restrict_with_error

  belongs_to :legal_entity
  belongs_to :general_account

  validates :name, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :stripe_mode, inclusion: { in: STRIPE_MODES }

  # Les règles de saisie d'un IBAN à l'écran (Comptabilité › Comptes de
  # trésorerie), dans leur propre contexte : `save(context: :iban_entry)`. Elles
  # ne tiennent pas en permanence — des comptes posés par l'API portent un
  # simple numéro de compte, que l'import CODA sait relire.
  validates :iban, iban: true, allow_blank: true, on: :iban_entry
  validate :iban_unique, on: :iban_entry

  # Rangé par groupes de quatre, comme la banque l'imprime : l'import compare
  # les chiffres, la forme ne compte que pour qui le lit.
  def self.format_iban(value)
    brut = value.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
    brut.empty? ? nil : brut.scan(/.{1,4}/).join(" ")
  end

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }
  scope :stripe, -> { where(kind: "stripe") }
  scope :stripe_ledger, -> { stripe.where(stripe_mode: "ledger") }

  def kind_label = KIND_LABELS.fetch(kind, kind)
  def stripe_mode_label = STRIPE_MODE_LABELS.fetch(stripe_mode, stripe_mode)

  # Le mode ne veut rien dire hors d'un compte Stripe : un compte bancaire porte
  # la valeur par défaut et personne ne doit la lire.
  def stripe? = kind == "stripe"
  def ledger? = stripe? && stripe_mode == "ledger"
  def per_payout? = stripe? && stripe_mode == "per_payout"
  def bank? = kind == "bank"

  private

  # Un IBAN porté par deux comptes, et l'import refuse les deux.
  def iban_unique
    return if iban.blank?

    chiffres = iban.gsub(/\D/, "")
    doublon = CashAccount.with_deleted { CashAccount.where.not(id: id).to_a }
                         .find { |c| c.iban.to_s.gsub(/\D/, "") == chiffres }
    errors.add(:iban, "est déjà porté par « #{doublon.name} »") if doublon
  end
end
