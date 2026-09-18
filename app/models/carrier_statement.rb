# Le relevé de rémunération d'un porteur d'activité (epic #244, phase 3).
#
# Une prestation tenue portait sa rémunération figée depuis la phase 1, mais
# rien ne la payait. Le relevé rassemble les prestations `held` d'une période,
# fige leur total, passe l'écriture et devient une dette à virer.
#
# Deux gestes, et l'ordre compte : GÉNÉRER produit un brouillon qu'on relit,
# ÉMETTRE en fait un document. Le second est irréversible — d'où le premier.
# (Même forme que `RevenueShareStatement`, issue #247.)
class CarrierStatement < ApplicationRecord
  include Payable

  STATUSES = %w[draft issued paid].freeze
  STATUS_LABELS = { "draft" => "Brouillon", "issued" => "Émis", "paid" => "Payé" }.freeze

  belongs_to :human
  has_many :carrier_statement_lines, dependent: :destroy
  has_many :experience_bookings, through: :carrier_statement_lines

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :total_fee_cents

  validates :period_from, :period_to, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :period_ends_after_it_starts

  before_validation :ensure_token

  scope :recent_first, -> { order(period_from: :desc, id: :desc) }
  scope :draft, -> { where(status: "draft") }
  scope :issued, -> { where(status: "issued") }
  scope :awaiting_payment, -> { where(status: "issued") }

  def status_label = STATUS_LABELS.fetch(status, status)
  def draft?  = status == "draft"
  def issued? = status == "issued"
  def paid?   = status == "paid"
  def posted? = posted_at.present?

  # La référence qui sert de communication de virement. Courte, stable, et
  # lisible sur un relevé bancaire.
  def reference = "ACT-#{id}-#{period_from.strftime('%Y%m')}"

  def period_label
    "#{I18n.l(period_from, format: '%-d %B %Y')} — #{I18n.l(period_to, format: '%-d %B %Y')}"
  end

  def mail_subject
    "Relevé d'activités #{period_label} — " \
      "#{ActionController::Base.helpers.number_to_currency(total_fee_cents / 100.0)}"
  end

  # Recalcule le total depuis les lignes. Utilisé tant que le relevé est
  # brouillon ; l'émission fige cette valeur et plus rien ne la touche.
  def recompute_total
    self.total_fee_cents = carrier_statement_lines.sum(:fee_cents)
  end

  # --- Contrat `Payable` (epic #240, phase 4) --------------------------------

  def payable_amount_cents = total_fee_cents.to_i
  def payable_beneficiary = human.name
  def payable_third_party = ThirdParty.for_human!(human)
  def payable_communication = reference
  def payable_reference = reference
  def payable_label = "Relevé d'activités — #{human.name}"
  def payable_path = Rails.application.routes.url_helpers.finance_carrier_statement_path(self)

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end

  def period_ends_after_it_starts
    return if period_from.blank? || period_to.blank? || period_to >= period_from

    errors.add(:period_to, "doit être postérieure au début de la période")
  end
end
