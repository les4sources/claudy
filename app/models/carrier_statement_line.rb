# Une prestation relevée (epic #244, phase 3).
#
# `experience_booking_id` est UNIQUE en base : une prestation n'est relevée
# qu'une fois. C'est l'invariant qui empêche de payer deux fois le même travail,
# et il tient au niveau de la base — pas seulement dans le service qui génère.
class CarrierStatementLine < ApplicationRecord
  belongs_to :carrier_statement
  belongs_to :experience_booking

  has_paper_trail

  monetize :fee_cents

  validates :fee_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :experience_booking_id, uniqueness: { message: "cette prestation est déjà relevée" }

  scope :chronological, -> { order(Arel.sql("occurred_on NULLS LAST"), :id) }

  def display_label = label.presence || experience_booking.experience&.name.to_s
end
