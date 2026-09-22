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

  # Ce qui empêche la suppression, nommé et compté — pas une catégorie.
  #
  # « Cette entité porte des exercices ou des écritures » est littéralement vrai
  # d'une entité qui ne porte qu'un exercice VIDE, et envoie pourtant
  # l'utilisateur désactiver là où supprimer l'exercice aurait suffi. Compter
  # chaque cause séparément est ce qui permet au refus de dire quoi aller
  # regarder.
  def deletion_blockers
    {
      fiscal_years: fiscal_years.count,
      cash_accounts: cash_accounts.count,
      journal_entries: journal_entries.count
    }.reject { |_kind, count| count.zero? }
  end

  def deletable? = deletion_blockers.empty?

  # Les exercices que la page des exercices accepte déjà de supprimer : ouverts
  # et sans écriture. La condition est recopiée d'elle — si elle change là-bas,
  # les deux doivent bouger ensemble, sinon le refus promet un bouton absent.
  def removable_fiscal_years
    fiscal_years.reject { |year| year.closed? || year.journal_entries.any? }
  end

  def closed_fiscal_years = fiscal_years.select(&:closed?)

  # Le seul obstacle tient-il à des exercices vides ? Alors la désactivation est
  # le mauvais conseil : trois clics suffisent à supprimer pour de bon.
  def blocked_only_by_empty_fiscal_years?
    return false if deletable?
    return false if cash_accounts.exists? || journal_entries.exists?

    removable_fiscal_years.size == fiscal_years.size
  end

  # L'exercice qui contient une date. C'est par lui que passe toute écriture :
  # sans exercice ouvert, on ne comptabilise pas — on le dit, plutôt que de
  # ranger l'écriture dans un exercice arbitraire.
  def fiscal_year_for(date)
    fiscal_years.find { |year| year.covers?(date) }
  end
end
