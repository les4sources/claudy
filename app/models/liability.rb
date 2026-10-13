# Une dette ou un litige SANS facture encodée (Michael, 2026-10-13) : la taxe
# communale d'hébergement qu'Yvoir réclame pour cinq ans (12 000 €, contestés
# en partie : on paiera entre 6 000 et 12 000 €), un arriéré, un risque connu.
#
# Trois montants, parce qu'un litige n'en a pas qu'un :
# - réclamé : ce que le créancier demande ;
# - la fourchette (bas, haut) : ce qu'on finira vraisemblablement par payer ;
# - RETENU : le montant que la gestion compte. Par défaut le haut de la
#   fourchette — la vue Comptabilité ne cherche pas à rassurer.
#
# Le retenu, moins ce qui est déjà payé, sort de la trésorerie à la date
# probable, en une fois ou en mensualités. Sans date, il sort AUJOURD'HUI,
# comme une dette échue de la file « À payer » : ne pas savoir quand on paiera
# ne dispense pas de payer.
#
# Rien n'est comptabilisé : c'est une prévision, comme `RecurringExpense`. Le
# jour où la facture arrive, on l'encode et on solde la dette ici.
# == Schema Information
#
# Table name: liabilities
#
#  id                 :bigint           not null, primary key
#  claimed_cents      :bigint
#  closed_on          :date
#  deleted_at         :datetime
#  expected_on        :date
#  high_cents         :bigint
#  installments       :integer          default(1), not null
#  kind               :string           default("debt"), not null
#  label              :string           not null
#  low_cents          :bigint
#  notes              :text
#  paid_cents         :bigint           default(0), not null
#  retained_cents     :bigint           not null
#  status             :string           default("open"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint
#  legal_entity_id    :bigint           not null
#  team_id            :bigint
#  third_party_id     :bigint
#
# Indexes
#
#  index_liabilities_on_deleted_at          (deleted_at)
#  index_liabilities_on_general_account_id  (general_account_id)
#  index_liabilities_on_legal_entity_id     (legal_entity_id)
#  index_liabilities_on_status              (status)
#  index_liabilities_on_team_id             (team_id)
#  index_liabilities_on_third_party_id      (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
class Liability < ApplicationRecord
  KINDS = %w[debt dispute risk].freeze
  KIND_LABELS = {
    "debt" => "Dette",
    "dispute" => "Litige",
    "risk" => "Risque"
  }.freeze
  KIND_HINTS = {
    "debt" => "Le montant est connu, il reste à payer (arriéré, remboursement promis).",
    "dispute" => "Le créancier réclame, on conteste tout ou partie.",
    "risk" => "Rien n'est encore réclamé, mais on sait que ça viendra."
  }.freeze
  STATUSES = %w[open settled dropped].freeze
  STATUS_LABELS = {
    "open" => "En cours",
    "settled" => "Soldée",
    "dropped" => "Abandonnée"
  }.freeze
  MAX_INSTALLMENTS = 120
  MONEY_FIELDS = %i[claimed low high retained paid].freeze

  Installment = Struct.new(:due_on, :amount_cents, keyword_init: true)

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  belongs_to :third_party, optional: true
  belongs_to :team, optional: true
  belongs_to :general_account, optional: true

  validates :label, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :retained_cents, numericality: { greater_than: 0 }
  validates :paid_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :claimed_cents, :low_cents, :high_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :installments, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_INSTALLMENTS }
  validate :range_is_ordered
  validate :retained_within_range
  validate :paid_within_retained

  before_save :stamp_closed_on

  scope :ordered, -> { order(:status, Arel.sql("expected_on IS NULL"), :expected_on, :label) }
  scope :open, -> { where(status: "open") }
  scope :closed, -> { where.not(status: "open") }

  # Les montants en euros pour les formulaires : on saisit « 12 000 », pas
  # 1200000. Une case vide efface le montant (sauf « déjà payé », qui retombe
  # à zéro).
  MONEY_FIELDS.each do |field|
    define_method(field) do
      cents = public_send(:"#{field}_cents")
      cents && (cents / 100.0)
    end

    define_method(:"#{field}=") do |value|
      cents = self.class.parse_euros(value)
      cents = 0 if cents.nil? && field == :paid
      public_send(:"#{field}_cents=", cents)
    end
  end

  def self.parse_euros(value)
    normalized = value.to_s.strip.delete(" ").delete(" ").delete(" ").tr(",", ".")
    normalized.present? ? (BigDecimal(normalized) * 100).round.to_i : nil
  rescue ArgumentError
    nil
  end

  # Les valeurs proposées à la création : le haut de la fourchette, ou à
  # défaut le montant réclamé. C'est un défaut, pas une règle — on retient
  # moins quand on a de bonnes raisons de le croire, et on l'écrit en note.
  def self.prudent_retained_cents(claimed_cents:, high_cents:)
    high_cents.presence || claimed_cents.presence
  end

  def open? = status == "open"
  def kind_label = KIND_LABELS.fetch(kind, kind)
  def status_label = STATUS_LABELS.fetch(status, status)
  def ranged? = low_cents.present? || high_cents.present?

  def remaining_cents = open? ? [retained_cents.to_i - paid_cents.to_i, 0].max : 0

  # Les mensualités qui restent à payer, chacune à sa date. La première tombe
  # à la date probable (aujourd'hui sans date) ; ce qui est déjà payé éteint
  # les premières. Une mensualité passée et impayée sort AUJOURD'HUI : la
  # trésorerie ne projette rien dans le passé.
  def schedule(today: Date.current)
    return [] unless open? && remaining_cents.positive?

    start = expected_on || today
    count = installments.to_i.clamp(1, MAX_INSTALLMENTS)
    base, extra = retained_cents.to_i.divmod(count)
    already_paid = paid_cents.to_i

    (0...count).filter_map do |index|
      amount = base + (index < extra ? 1 : 0)
      covered = [already_paid, amount].min
      already_paid -= covered
      due = amount - covered
      next unless due.positive?

      Installment.new(due_on: [start >> index, today].max, amount_cents: due)
    end
  end

  # La date de la dernière mensualité : « jusqu'en mars 2027 ».
  def last_due_on
    return nil if expected_on.nil?

    expected_on >> (installments.to_i - 1)
  end

  private

  def range_is_ordered
    return if low_cents.nil? || high_cents.nil? || low_cents <= high_cents

    errors.add(:low_cents, "doit être inférieur ou égal au haut de la fourchette")
  end

  def retained_within_range
    return if retained_cents.nil?

    if low_cents && retained_cents < low_cents
      errors.add(:retained_cents, "est sous le bas de la fourchette")
    elsif high_cents && retained_cents > high_cents
      errors.add(:retained_cents, "dépasse le haut de la fourchette")
    end
  end

  def paid_within_retained
    return if retained_cents.nil? || paid_cents.to_i <= retained_cents

    errors.add(:paid_cents, "dépasse le montant retenu")
  end

  def stamp_closed_on
    if open?
      self.closed_on = nil
    elsif closed_on.nil?
      self.closed_on = Date.current
    end
  end
end
