# La part d'UN organisateur sur un événement réglé (epic #245, phase 3).
#
# C'est un `Payable` : elle apparaît sur « À payer » avec l'IBAN de
# l'organisateur et le nom de l'événement en communication, et elle se solde par
# RAPPROCHEMENT — l'allocation de la ligne bancaire sur le `440000` avec cette
# part en `document`. Jamais par une case à cocher : un état qui ne sait que
# monter ment (cf. `Payable`).
class EventSettlementLine < ApplicationRecord
  include Payable

  belongs_to :event_settlement
  belongs_to :human

  has_paper_trail

  monetize :amount_cents

  validates :weight, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :human_id, uniqueness: { scope: :event_settlement_id }

  delegate :event, to: :event_settlement

  # --- Contrat Payable -------------------------------------------------------

  def payable_amount_cents = amount_cents.to_i
  def payable_beneficiary = human.name
  def payable_third_party = ThirdParty.for_human!(human)
  def payable_communication = event.name
  def payable_reference = "EVT-#{event_settlement_id}-#{id}"
  def payable_label = "Part organisateur — #{event.name}"
  def payable_path = Rails.application.routes.url_helpers.event_path(event, tab: "comptabilite")

  # Le `paid_on` est une TRACE de ce que le rapprochement a constaté, pas la
  # source de vérité : c'est `payable_settled?` qui décide.
  def mark_paid_on!(date)
    update!(paid_on: date) if paid_on.blank?
  end
end
