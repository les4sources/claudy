# Une immobilisation du registre (revue expert-comptable du 2026-10-20) : un
# bien qui sert plusieurs années — mobilier, machines, une yourte — et dont le
# coût se répartit sur sa durée d'utilisation par des dotations annuelles.
#
# L'achat lui-même est déjà au grand livre (une facture ou une ligne de banque
# affectée au compte d'immobilisation) : le registre ne le repasse pas. Il dit
# ce qui reste à amortir et produit chaque année l'écriture de dotation.
#
# Amortissement LINÉAIRE, prorata temporis au mois : un bien acheté en
# septembre prend quatre mois de dotation la première année. Le comptable peut
# le contester ; il ne peut pas reprocher au registre d'avoir été flou.
#
# `prior_depreciation_cents` reprend ce qui a été amorti AVANT Claudy (les
# 82 000 € déjà au 240001). Une dotation rattrape l'écart si l'historique en a
# laissé : elle vise toujours le cumul théorique à la fin de l'exercice.
class FixedAsset < ApplicationRecord
  DEFAULT_EXPENSE_CODE = "630100".freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :general_account
  belongs_to :depreciation_account, class_name: "GeneralAccount"
  belongs_to :expense_account, class_name: "GeneralAccount"
  belongs_to :team, optional: true
  has_many :depreciations, class_name: "FixedAssetDepreciation", dependent: :restrict_with_error

  # Les montants se saisissent en euros (« 12 000,50 »), comme une dette : la
  # même lecture que `Liability.parse_euros`. « Amorti avant Claudy » vide
  # vaut zéro.
  %i[acquisition prior_depreciation].each do |field|
    define_method(field) do
      cents = public_send(:"#{field}_cents")
      cents && (cents / 100.0)
    end

    define_method(:"#{field}=") do |value|
      cents = Liability.parse_euros(value)
      cents = 0 if cents.nil? && field == :prior_depreciation
      public_send(:"#{field}_cents=", cents)
    end
  end

  validates :name, :acquired_on, presence: true
  validates :acquisition_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :useful_life_years, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :prior_depreciation_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :prior_within_acquisition
  validate :accounts_in_their_class
  validate :disposed_after_acquisition

  scope :ordered, -> { order(:acquired_on, :name) }

  def disposed? = disposed_on.present?

  def annuity_cents = (acquisition_cents.to_r / useful_life_years).round

  # Ce que le plan d'amortissement a consommé au soir d'une date : un mois
  # entamé compte pour un mois, plafonné à la valeur d'acquisition.
  def theoretical_cumulative_cents(date)
    return 0 if date < acquired_on

    months = (date.year * 12 + date.month) - (acquired_on.year * 12 + acquired_on.month) + 1
    [acquisition_cents, (acquisition_cents * months.to_r / (useful_life_years * 12)).round].min
  end

  def booked_cents(except: nil)
    list = depreciations.to_a
    list = list.reject { |depreciation| depreciation.fiscal_year_id == except.id } if except
    list.sum(&:amount_cents)
  end

  def depreciated_cents = prior_depreciation_cents + booked_cents
  def net_book_value_cents = acquisition_cents - depreciated_cents

  def depreciation_for(fiscal_year) = depreciations.find { |depreciation| depreciation.fiscal_year_id == fiscal_year.id }

  # La dotation qu'il reste à passer sur un exercice : le cumul théorique à sa
  # fin (ou à la sortie du bien), moins ce qui est déjà amorti. Zéro si elle
  # est déjà passée, si le bien n'est pas encore acquis ou s'il est sorti.
  def depreciation_due_cents(fiscal_year)
    return 0 if fiscal_year.legal_entity_id != legal_entity_id
    return 0 if acquired_on > fiscal_year.ends_on
    return 0 if disposed_on && disposed_on < fiscal_year.starts_on
    return 0 if depreciation_for(fiscal_year)

    already = prior_depreciation_cents + booked_cents(except: fiscal_year)
    cap = [fiscal_year.ends_on, disposed_on].compact.min
    [[theoretical_cumulative_cents(cap) - already, 0].max, acquisition_cents - already].min
  end

  def self.missing_depreciation(fiscal_year)
    where(legal_entity_id: fiscal_year.legal_entity_id).includes(:depreciations)
      .select { |asset| asset.depreciation_due_cents(fiscal_year).positive? }
  end

  private

  def prior_within_acquisition
    return if acquisition_cents.blank? || prior_depreciation_cents.to_i <= acquisition_cents

    errors.add(:prior_depreciation_cents, "dépasse la valeur d'acquisition")
  end

  def accounts_in_their_class
    errors.add(:general_account, "doit être un compte de classe 2") if general_account && general_account.klass != 2
    errors.add(:depreciation_account, "doit être un compte de classe 2") if depreciation_account && depreciation_account.klass != 2
    errors.add(:expense_account, "doit être un compte de charge (classe 6)") if expense_account && expense_account.klass != 6
  end

  def disposed_after_acquisition
    return if disposed_on.blank? || acquired_on.blank? || disposed_on >= acquired_on

    errors.add(:disposed_on, "précède l'acquisition")
  end
end
