# == Schema Information
#
# Table name: spaces
#
#  id          :bigint           not null, primary key
#  capacity    :integer          default(1), not null
#  code        :string
#  deleted_at  :datetime
#  description :text
#  name        :string
#  position    :integer          default(999)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Space < ApplicationRecord
  has_many :space_reservations

  has_soft_deletion default_scope: true

  default_scope -> { order(:position) }

  validates :name, presence: true
  validates :capacity,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  def available_on?(date)
    !booked_on?(date)
  end

  # Occupé = le nombre de groupes BLOQUANTS ce jour atteint la capacité.
  # capacity 1 (défaut) → un seul groupe, comportement historique des salles.
  # capacity >1 → espace multi-groupe (camping : Bois, Pâture est/ouest).
  def booked_on?(date)
    blocking_reservations_on(date) >= capacity
  end

  # Places (groupes) encore disponibles ce jour-là.
  def remaining_capacity_on(date)
    [capacity - blocking_reservations_on(date), 0].max
  end

  # Espace pouvant accueillir plusieurs groupes simultanément.
  def shared?
    capacity > 1
  end

  private

  # Renommée depuis `confirmed_reservations_on` (Michael 2026-09-08) : elle ne
  # compte plus les seuls `confirmed` mais tous les `Stay::BLOCKING_STATUSES`,
  # `pre_confirmed` compris. Garder l'ancien nom aurait été un mensonge à
  # chaque relecture.
  def blocking_reservations_on(date)
    SpaceReservation.includes(:space_booking)
                    .where(
                      date: date,
                      space: self.id,
                      space_booking: { status: Stay::BLOCKING_STATUSES }
                    ).count
  end
end
