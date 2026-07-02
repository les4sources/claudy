# == Schema Information
#
# Table name: spaces
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  code        :string
#  deleted_at  :datetime
#  position    :integer          default(999)
#
class Space < ApplicationRecord
  has_many :space_reservations

  has_soft_deletion default_scope: true

  default_scope -> { order(:position) }

  def available_on?(date)
    !booked_on?(date)
  end

  # Occupé = le nombre de groupes confirmés ce jour atteint la capacité.
  # capacity 1 (défaut) → un seul groupe, comportement historique des salles.
  # capacity >1 → espace multi-groupe (camping : Bois, Pâture est/ouest).
  def booked_on?(date)
    confirmed_reservations_on(date) >= capacity
  end

  # Places (groupes) encore disponibles ce jour-là.
  def remaining_capacity_on(date)
    [capacity - confirmed_reservations_on(date), 0].max
  end

  # Espace pouvant accueillir plusieurs groupes simultanément.
  def shared?
    capacity > 1
  end

  private

  def confirmed_reservations_on(date)
    SpaceReservation.includes(:space_booking)
                    .where(
                      date: date,
                      space: self.id,
                      space_booking: { status: "confirmed" }
                    ).count
  end
end
