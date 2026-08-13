# == Schema Information
#
# Table name: account_statements
#
#  id                    :bigint           not null, primary key
#  closing_balance_cents :bigint           default(0), not null
#  credits_cents         :bigint           default(0), not null
#  debits_cents          :bigint           default(0), not null
#  deleted_at            :datetime
#  issued_at             :datetime
#  last_reminder_at      :datetime
#  opening_balance_cents :bigint           default(0), not null
#  period_month          :date             not null
#  reminders_count       :integer          default(0), not null
#  sent_at               :datetime
#  status                :string           default("draft"), not null
#  token                 :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  member_account_id     :bigint           not null
#
# Indexes
#
#  index_account_statements_on_deleted_at                          (deleted_at)
#  index_account_statements_on_member_account_id                   (member_account_id)
#  index_account_statements_on_member_account_id_and_period_month  (member_account_id,period_month) UNIQUE
#  index_account_statements_on_token                               (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (member_account_id => member_accounts.id)
#
class AccountStatement < ApplicationRecord
  STATUSES = %w[draft issued sent settled].freeze
  STATUS_LABELS = {
    "draft" => "Brouillon",
    "issued" => "Émis",
    "sent" => "Envoyé",
    "settled" => "Réglé"
  }.freeze

  has_soft_deletion default_scope: true
  has_paper_trail

  belongs_to :member_account
  has_many :account_entries, dependent: :nullify

  monetize :opening_balance_cents
  monetize :debits_cents
  monetize :credits_cents
  monetize :closing_balance_cents

  validates :period_month, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :period_month, uniqueness: { scope: :member_account_id }
  validate :balances_add_up
  validate :opens_where_previous_closed

  before_validation :normalize_period
  before_validation :ensure_token

  scope :recent_first, -> { order(period_month: :desc, id: :desc) }
  scope :for_month, ->(month) { where(period_month: month.beginning_of_month) }

  def status_label = STATUS_LABELS.fetch(status, status)
  def issued? = issued_at.present?
  def settled? = status == "settled"

  def previous
    self.class.where(member_account_id: member_account_id)
        .where(period_month: ...period_month)
        .order(period_month: :desc)
        .first
  end

  # Objet du mail : le CODE y figure pour qu'un copier-coller paresseux produise
  # quand même une communication exploitable au moment du virement.
  def mail_subject
    "Ton décompte — #{I18n.l(period_month, format: '%B %Y')} — " \
      "#{ActionController::Base.helpers.number_to_currency(closing_balance_cents / 100.0)} — " \
      "#{member_account.code}"
  end

  private

  def normalize_period
    self.period_month = period_month.beginning_of_month if period_month.present?
  end

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end

  def balances_add_up
    return if closing_balance_cents == opening_balance_cents + debits_cents + credits_cents

    errors.add(:closing_balance_cents, "doit être égal à ouverture + débits + crédits")
  end

  # L'invariant qui rend la chaîne des décomptes auditable de bout en bout :
  # l'ouverture d'un mois est la clôture du précédent. Si elle ne l'est pas,
  # c'est qu'une écriture s'est glissée entre les deux — et le décompte envoyé
  # mentirait sans que personne ne puisse le voir.
  def opens_where_previous_closed
    previous_statement = previous
    return if previous_statement.nil?
    return if opening_balance_cents == previous_statement.closing_balance_cents

    errors.add(:opening_balance_cents,
               "doit reprendre la clôture du décompte précédent " \
               "(#{previous_statement.closing_balance_cents} cents)")
  end
end
