# Le justificatif mensuel des frais Stripe (epic #240, phase 5).
#
# Ce que ce document N'EST PAS : une facture d'achat. Les frais Stripe sont déjà
# comptabilisés par la ventilation des versements — les enregistrer une seconde
# fois les compterait deux fois. Il n'y a donc ni écriture, ni statut, ni
# paiement ici : seulement le PDF téléchargé du Dashboard Stripe, le montant
# qu'il déclare, et l'écart avec ce que Claudy a compté. L'écart s'affiche ; il
# ne corrige jamais rien d'office.
class StripeFeeInvoice < ApplicationRecord
  has_one_attached :document

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :declared_fee_cents, allow_nil: true

  validates :account_key, presence: true,
                          inclusion: { in: StripeService::ACCOUNTS.keys.map(&:to_s), message: "compte Stripe inconnu" }
  validates :period_month, presence: true
  validates :declared_fee_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :period_month_is_a_first_of_month
  validate :unique_among_live

  scope :for_account, ->(key) { where(account_key: key.to_s) }
  scope :for_month, ->(date) { where(period_month: date.to_date.beginning_of_month) }
  scope :antichronological, -> { order(period_month: :desc, account_key: :asc) }

  before_validation :normalise_period_month

  def self.find_for(account_key, month)
    for_account(account_key).for_month(month).first
  end

  def account_label = StripeService.label_for(account_key)

  def month_label = I18n.l(period_month, format: "%B %Y")

  # L'écart entre ce que Stripe facture et ce que Claudy a compté. `nil` quand
  # rien n'est déclaré : on ne compare pas un chiffre à du vide.
  def gap_cents(counted_cents)
    return nil if declared_fee_cents.nil?

    declared_fee_cents - counted_cents.to_i
  end

  private

  def normalise_period_month
    self.period_month = period_month.beginning_of_month if period_month.present?
    self.account_key = account_key.to_s if account_key.present?
  end

  def period_month_is_a_first_of_month
    return if period_month.blank? || period_month == period_month.beginning_of_month

    errors.add(:period_month, "doit être le premier jour du mois")
  end

  # Unicité sur les lignes VIVANTES, comme l'index partiel en base : un
  # justificatif retiré par erreur doit pouvoir être redéposé.
  def unique_among_live
    return if account_key.blank? || period_month.blank?

    scope = self.class.for_account(account_key).for_month(period_month)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:period_month, "un justificatif existe déjà pour ce compte et ce mois")
  end
end
