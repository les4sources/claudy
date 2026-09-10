# Le relevé d'une période pour un accord de partage (issue #247).
#
# Il naît `draft` — une proposition qu'on relit — puis devient `issued` : à ce
# moment les montants sont figés, l'écriture est passée, l'email est parti. Une
# réservation modifiée après coup ne réécrit JAMAIS un relevé émis : l'écart
# revient au relevé suivant sous forme de régularisation (décision 5). C'est ce
# qui rend le document opposable aux propriétaires.
# == Schema Information
#
# Table name: revenue_share_statements
#
#  id                         :bigint           not null, primary key
#  base_cents                 :bigint           default(0), not null
#  deleted_at                 :datetime
#  issued_at                  :datetime
#  paid_on                    :date
#  period_from                :date             not null
#  period_to                  :date             not null
#  posted_at                  :datetime
#  sent_at                    :datetime
#  share_cents                :bigint           default(0), not null
#  status                     :string           default("draft"), not null
#  token                      :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  revenue_share_agreement_id :bigint           not null
#
# Indexes
#
#  index_revenue_share_statements_on_deleted_at  (deleted_at)
#  index_revenue_share_statements_on_token       (token) UNIQUE
#  index_rss_on_agreement_and_period             (revenue_share_agreement_id,period_from) UNIQUE
#  index_rss_on_agreement_id                     (revenue_share_agreement_id)
#
# Foreign Keys
#
#  fk_rails_...  (revenue_share_agreement_id => revenue_share_agreements.id)
#
class RevenueShareStatement < ApplicationRecord
  STATUSES = %w[draft issued paid].freeze
  STATUS_LABELS = {
    "draft"  => "Brouillon",
    "issued" => "Émis",
    "paid"   => "Payé"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :revenue_share_agreement
  has_many :revenue_share_statement_lines, dependent: :destroy
  has_one :lodging, through: :revenue_share_agreement

  validates :period_from, :period_to, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :period_from, uniqueness: { scope: :revenue_share_agreement_id }
  validate :period_ends_after_it_starts

  before_validation :ensure_token

  scope :recent_first, -> { order(period_from: :desc, id: :desc) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def draft?  = status == "draft"
  def issued? = status == "issued"
  def paid?   = status == "paid"
  def posted? = posted_at.present?

  def period_label = revenue_share_agreement.period_label_for(period_from)

  # La référence qui sert de communication de virement. Courte, stable, et
  # lisible sur un relevé bancaire.
  def reference = "REV-#{id}-#{period_from.strftime('%Y%m')}"

  def mail_subject
    "Reversement #{revenue_share_agreement.lodging&.name} — #{period_label} — " \
      "#{ActionController::Base.helpers.number_to_currency(share_cents / 100.0)}"
  end

  # Recalcule base et part depuis les lignes. Utilisé tant que le relevé est
  # brouillon ; l'émission fige ces mêmes valeurs et plus rien ne les touche.
  def recompute_totals
    base = revenue_share_statement_lines.sum(:amount_cents)
    self.base_cents = base
    self.share_cents = revenue_share_agreement.share_of(base)
  end

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end

  def period_ends_after_it_starts
    return if period_from.blank? || period_to.blank? || period_to >= period_from

    errors.add(:period_to, "doit être postérieure au début de la période")
  end
end
