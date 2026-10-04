# Le contrôle mensuel d'un carnet (epic #359, phase 5).
#
# Personne n'encode les lignes des carnets Épicerie et Boulangerie : une fois
# par mois, on additionne les feuilles et on saisit trois totaux — tout ce qui
# a été noté, ce qui a été noté payé par QR ou virement, ce qui a été noté payé
# en espèces. Claudy met en face ce que la banque a reçu au mot-clé du carnet.
#
# **L'ÉCART SE FIGE À LA VALIDATION**, comme pour un comptage de caisse
# (`CashCount`) : `bank_received_cents` et `gap_cents` sont écrits à ce
# moment-là et ne bougent plus, même si un virement est affecté après coup. Un
# écart recalculé à l'affichage se dissout tout seul — c'est précisément ce qui
# empêche de mesurer la fuite mois après mois.
#
# L'artisanat n'a pas de contrôle ici : chaque artisan encode ses ventes, et
# son relevé porte déjà déclaré / reçu / espèces (phase 4).
class ShopMonthlyCheck < ApplicationRecord
  CHANNELS = %w[grocery bread].freeze
  STATUSES = %w[draft validated].freeze
  STATUS_LABELS = { "draft" => "Brouillon", "validated" => "Validé" }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :validated_by, class_name: "User", optional: true

  before_validation :normalize_period

  validates :channel, inclusion: { in: CHANNELS }
  validates :period_month, presence: true
  validates :channel, uniqueness: { scope: :period_month, conditions: -> { where(deleted_at: nil) },
                                    message: "a déjà un contrôle pour ce mois" }
  validates :status, inclusion: { in: STATUSES }
  validates :sheets_total_cents, :transfer_total_cents, :cash_total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :validated_check_is_immutable, on: :update

  scope :ordered, -> { order(period_month: :desc, channel: :asc) }
  scope :validated, -> { where(status: "validated") }
  scope :for_month, ->(month) { where(period_month: month.beginning_of_month) }

  # Ce que la banque a reçu pour un carnet sur un mois : les affectations au
  # compte de produit du carnet, sur un compte bancaire (pas la caisse — les
  # espèces se comptent à part, sinon la ligne « Caisse épicerie » elle-même
  # passerait pour un virement), lignes exclues mises de côté.
  def self.bank_received_cents(channel, month)
    account = ShopSetting.current.revenue_account(channel)
    return 0 if account.nil?

    month = month.beginning_of_month
    CashAllocation.joins(cash_entry: :cash_account)
                  .where(general_account_id: account.id)
                  .where.not(cash_accounts: { kind: "cash" })
                  .where(cash_entries: { deleted_at: nil, entry_date: month..month.end_of_month })
                  .where.not(cash_entries: { status: "excluded" })
                  .sum(:amount_cents)
  end

  def draft? = status == "draft"
  def validated? = status == "validated"
  def status_label = STATUS_LABELS.fetch(status, status)
  def notebook = channel.to_sym
  def notebook_label = ShopSetting::NOTEBOOK_LABELS.fetch(notebook)
  def keyword = ShopSetting::NOTEBOOK_KEYWORDS.fetch(notebook)
  def period_label = I18n.l(period_month, format: "%B %Y")

  def live_bank_received_cents = self.class.bank_received_cents(channel, period_month)

  # Validé : le chiffre figé. Brouillon : ce que la banque dit aujourd'hui.
  def displayed_bank_received_cents = validated? ? bank_received_cents.to_i : live_bank_received_cents

  # Positif : on a noté plus que ce qui est entré (impayé, mauvais QR, espèces
  # manquantes). Négatif : il est entré plus que ce qui a été noté.
  def displayed_gap_cents
    return gap_cents.to_i if validated?

    sheets_total_cents - displayed_bank_received_cents - cash_total_cents
  end

  # Les lignes des feuilles sans case « payé par » cochée : noté, mais ni QR,
  # ni virement, ni caisse.
  def unmarked_cents = sheets_total_cents - transfer_total_cents - cash_total_cents

  # QR et virements notés sur les feuilles, face à ce que la banque a reçu.
  def transfer_gap_cents = transfer_total_cents - displayed_bank_received_cents

  def balanced? = displayed_gap_cents.zero?

  private

  def normalize_period
    self.period_month = period_month&.beginning_of_month
  end

  # Un contrôle validé est un fait daté : il ne se rejoue pas.
  def validated_check_is_immutable
    return unless status_was == "validated"

    figes = %w[channel period_month sheets_total_cents transfer_total_cents cash_total_cents
               bank_received_cents gap_cents status validated_at validated_by_id]
    return if (changed & figes).empty?

    errors.add(:base, "Un contrôle validé ne se modifie plus.")
  end
end
