# Un accord de partage de revenus sur un hébergement (issue #247).
#
# La tiny house appartient à une famille tierce : les 4 Sources encaissent la
# location (réservation Airbnb réencodée à la main dans Claudy) et reversent la
# moitié. Le modèle est générique parce que le cas ne l'est pas : dès qu'un
# second hébergement sera partagé, il suffira d'un accord de plus — pas d'une
# migration.
#
# La PÉRIODICITÉ est un réglage de l'accord, pas une branche de code. Passer du
# trimestriel au mensuel se fait dans le formulaire ; « générer le relevé »
# propose alors le mois clos au lieu du trimestre clos.
# == Schema Information
#
# Table name: revenue_share_agreements
#
#  id                         :bigint           not null, primary key
#  active                     :boolean          default(TRUE), not null
#  beneficiary_email          :string
#  beneficiary_iban           :text
#  beneficiary_name           :string           not null
#  deleted_at                 :datetime
#  ends_on                    :date
#  period                     :string           default("quarterly"), not null
#  share_percent              :integer          default(50), not null
#  starts_on                  :date             not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  beneficiary_third_party_id :bigint
#  lodging_id                 :bigint           not null
#
# Indexes
#
#  index_revenue_share_agreements_on_active                      (active)
#  index_revenue_share_agreements_on_beneficiary_third_party_id  (beneficiary_third_party_id)
#  index_revenue_share_agreements_on_deleted_at                  (deleted_at)
#  index_revenue_share_agreements_on_lodging_id                  (lodging_id)
#
# Foreign Keys
#
#  fk_rails_...  (beneficiary_third_party_id => third_parties.id)
#  fk_rails_...  (lodging_id => lodgings.id)
#
class RevenueShareAgreement < ApplicationRecord
  PERIODS = %w[quarterly monthly].freeze
  PERIOD_LABELS = {
    "quarterly" => "Trimestrielle",
    "monthly"   => "Mensuelle"
  }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  encrypts :beneficiary_iban

  belongs_to :lodging
  belongs_to :beneficiary_third_party, class_name: "ThirdParty", optional: true
  has_many :revenue_share_statements, dependent: :restrict_with_error

  before_validation :normalize_iban

  validates :beneficiary_name, presence: true
  validates :period, inclusion: { in: PERIODS }
  validates :starts_on, presence: true
  validates :share_percent,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :beneficiary_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :beneficiary_iban, iban: true, allow_blank: true
  validate :ends_after_starts

  scope :ordered, -> { order(active: :desc, id: :asc) }
  scope :actives, -> { where(active: true) }

  def period_label = PERIOD_LABELS.fetch(period, period)
  def quarterly? = period == "quarterly"
  def monthly?   = period == "monthly"

  # L'IBAN ne s'affiche jamais en entier hors du formulaire (même règle que les
  # artisans en dépôt-vente).
  def iban_masked
    return nil if beneficiary_iban.blank?

    "•••• #{beneficiary_iban.last(4)}"
  end

  def running_on?(date = Date.current)
    return false unless active?
    return false if starts_on.present? && date < starts_on
    return false if ends_on.present? && date > ends_on

    true
  end

  # La part d'une base, arrondie au cent. `round` sur un Rational plutôt qu'une
  # division entière : 501 € à 50 % vaut 250,50 € et non 250 €.
  def share_of(base_cents)
    (base_cents.to_i * share_percent / 100.0).round
  end

  # Les bornes de TOUTES les périodes closes de l'accord, de la plus récente à
  # la plus ancienne. La dernière période close est celle dont la fin est déjà
  # passée : on ne relève jamais un trimestre en cours, il bougerait encore.
  def closed_periods(today: Date.current, limit: 8)
    periods = []
    cursor = period_start_for(today)

    limit.times do
      cursor = previous_period_start(cursor)
      break if cursor < starts_on.beginning_of_month && periods.any?

      periods << [cursor, period_end_for(cursor)]
    end

    periods.reject { |from, _to| ends_on.present? && from > ends_on }
  end

  # La première période close pas encore relevée — ce que propose « Générer ».
  def next_period_to_report(today: Date.current)
    reported = revenue_share_statements.pluck(:period_from)
    closed_periods(today: today).reverse.find { |from, _to| reported.exclude?(from) }
  end

  def period_start_for(date)
    monthly? ? date.beginning_of_month : date.beginning_of_quarter
  end

  def period_end_for(from)
    monthly? ? from.end_of_month : from.end_of_quarter
  end

  def period_label_for(from)
    return I18n.l(from, format: "%B %Y") if monthly?

    "T#{((from.month - 1) / 3) + 1} #{from.year}"
  end

  private

  def previous_period_start(start)
    monthly? ? (start - 1.month).beginning_of_month : (start - 3.months).beginning_of_quarter
  end

  def normalize_iban
    self.beneficiary_iban = beneficiary_iban.to_s.gsub(/\s+/, "").upcase.presence
  end

  def ends_after_starts
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "doit être postérieure à la date de début")
  end
end
