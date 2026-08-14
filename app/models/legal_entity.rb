# Une entité juridique — ce qui possède, ce qui doit, ce qui facture.
#
# Aux 4 Sources il y en a trois qui coexistent : la Société simple porte les
# travaux, la Fondation porte le lieu, la SRL porte l'activité commerciale. La
# frontière entre elles n'est pas décorative : une facture de travaux payée
# depuis le compte de la Fondation reste une charge de la Société simple, et
# c'est cette distinction qui rend le document opposable face à un tiers.
# == Schema Information
#
# Table name: legal_entities
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  deleted_at :datetime
#  form       :string           not null
#  name       :string           not null
#  vat_number :string
#  vat_regime :string           default("exempt"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_legal_entities_on_deleted_at  (deleted_at)
#  index_legal_entities_on_name        (name) UNIQUE
#
class LegalEntity < ApplicationRecord
  FORMS = %w[simple_company foundation srl].freeze
  FORM_LABELS = {
    "simple_company" => "Société simple",
    "foundation" => "Fondation",
    "srl" => "SRL"
  }.freeze

  VAT_REGIMES = %w[exempt subject franchise].freeze
  VAT_REGIME_LABELS = {
    "exempt" => "Exemptée",
    "subject" => "Assujettie",
    "franchise" => "Franchise"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  has_many :fiscal_years, dependent: :restrict_with_error
  has_many :cash_accounts, dependent: :restrict_with_error
  has_many :journal_entries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :form, inclusion: { in: FORMS }
  validates :vat_regime, inclusion: { in: VAT_REGIMES }

  scope :ordered, -> { order(:name) }
  scope :actives, -> { where(active: true) }

  def form_label = FORM_LABELS.fetch(form, form)
  def vat_regime_label = VAT_REGIME_LABELS.fetch(vat_regime, vat_regime)

  # L'exercice qui contient une date. C'est par lui que passe toute écriture :
  # sans exercice ouvert, on ne comptabilise pas — on le dit, plutôt que de
  # ranger l'écriture dans un exercice arbitraire.
  def fiscal_year_for(date)
    fiscal_years.find { |year| year.covers?(date) }
  end
end
