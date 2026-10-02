# Une charge fixe de la maison (2026-09-30) : l'abonnement Voo, une assurance,
# un remboursement d'emprunt. Écrite UNE fois — montant, fréquence, première
# échéance — elle projette ses occurrences dans la trésorerie.
#
# Ce n'est PAS une dette : rien n'est comptabilisé, rien n'entre dans la file
# « À payer ». C'est une prévision. La vraie facture, quand elle est encodée,
# prend sa place dans la projection pour la période qu'elle couvre (voir
# `Finance::Treasury`) ; le vrai prélèvement arrive par le relevé CODA.
#
# Les occurrences se déduisent TOUJOURS de la première échéance, par pas de 1,
# 3 ou 12 mois — comme l'échéancier comptable : un 31 janvier ne dérive pas en
# 28 le mois suivant puis en 28 pour toujours.
# == Schema Information
#
# Table name: recurring_expenses
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  amount_cents       :bigint           not null
#  deleted_at         :datetime
#  ends_on            :date
#  first_due_on       :date             not null
#  frequency          :string           default("monthly"), not null
#  label              :string           not null
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  general_account_id :bigint
#  legal_entity_id    :bigint           not null
#  third_party_id     :bigint
#
# Indexes
#
#  index_recurring_expenses_on_deleted_at          (deleted_at)
#  index_recurring_expenses_on_general_account_id  (general_account_id)
#  index_recurring_expenses_on_legal_entity_id     (legal_entity_id)
#  index_recurring_expenses_on_third_party_id      (third_party_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_account_id => general_accounts.id)
#  fk_rails_...  (legal_entity_id => legal_entities.id)
#  fk_rails_...  (third_party_id => third_parties.id)
#
class RecurringExpense < ApplicationRecord
  FREQUENCIES = %w[monthly quarterly yearly].freeze
  FREQUENCY_LABELS = {
    "monthly" => "Chaque mois",
    "quarterly" => "Chaque trimestre",
    "yearly" => "Chaque année"
  }.freeze
  FREQUENCY_MONTHS = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.freeze

  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :legal_entity
  # Facultatif : un prélèvement se prévoit avant qu'on ait créé son tiers. Sans
  # tiers, pas de remplacement par la vraie facture — l'estimation reste.
  belongs_to :third_party, optional: true
  belongs_to :general_account, optional: true

  validates :label, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :first_due_on, presence: true
  validate :ends_after_first_due

  scope :ordered, -> { order(:label) }
  scope :actives, -> { where(active: true) }

  def frequency_label = FREQUENCY_LABELS.fetch(frequency, frequency)

  # Le préremplissage « Cette charge revient » depuis une facture d'achat : son
  # fournisseur, son montant, son compte, et l'échéance suivante supposée un
  # mois plus tard — la fréquence la plus courante, qu'on corrige d'un clic.
  def self.prefill_from(invoice)
    base = invoice.due_on || invoice.issued_on
    {
      label: invoice.third_party&.name,
      third_party_id: invoice.third_party_id,
      legal_entity_id: invoice.legal_entity_id,
      general_account_id: invoice.purchase_invoice_lines.first&.general_account_id,
      amount: invoice.total_cents.to_i / 100.0,
      frequency: "monthly",
      first_due_on: base && (base >> 1)
    }.compact
  end

  # Le montant en euros pour les formulaires : on saisit « 67,76 », pas 6776.
  def amount
    amount_cents && (amount_cents / 100.0)
  end

  def amount=(value)
    normalized = value.to_s.strip.delete(" ").tr(",", ".")
    self.amount_cents = normalized.present? ? (BigDecimal(normalized) * 100).round.to_i : nil
  rescue ArgumentError
    self.amount_cents = nil
  end

  # Les dates d'échéance comprises entre `from` et `to` inclus.
  def occurrences_between(from, to)
    return [] if first_due_on.blank?

    step = FREQUENCY_MONTHS.fetch(frequency)
    last = [to, ends_on].compact.min
    dates = []
    index = 0
    loop do
      due_on = first_due_on >> (index * step)
      break if due_on > last

      dates << due_on if due_on >= from
      index += 1
    end
    dates
  end

  def next_due_on(from = Date.current)
    occurrences_between(from, from >> 12).first
  end

  # La période qu'une occurrence représente : c'est dans cette fenêtre qu'une
  # vraie facture du même tiers la remplace.
  def period_for(due_on)
    case frequency
    when "monthly" then due_on.all_month
    when "quarterly" then due_on.all_quarter
    when "yearly" then due_on.all_year
    end
  end

  # Ce que ça coûte sur un an, pour comparer un abonnement mensuel à une
  # assurance annuelle sans calcul de tête.
  def yearly_cents = amount_cents.to_i * (12 / FREQUENCY_MONTHS.fetch(frequency))

  private

  def ends_after_first_due
    return if ends_on.blank? || first_due_on.blank? || ends_on >= first_due_on

    errors.add(:ends_on, "doit suivre la première échéance")
  end
end
