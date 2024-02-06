# == Schema Information
#
# Table name: lodgings
#
#  id                      :bigint           not null, primary key
#  name                    :string
#  description             :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  summary                 :string
#  price_night_cents       :integer          default(0), not null
#  party_hall_availability :boolean
#  weekend_discount_cents  :integer          default(0), not null
#  deleted_at              :datetime
#
class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms
  has_many :bookings
  has_many :unavailabilities

  monetize :price_night_cents

  has_soft_deletion default_scope: true

  def available_between?(from_date, to_date)
    # none of the lodging rooms has a confirmed reservation
    Reservation.includes(:booking)
               .where(
                 date: from_date..to_date,
                 room: rooms.pluck(:id),
                 booking: { status: "confirmed" }
               ).none? && unavailabilities.where(date: from_date..to_date).none?
  end

  def available_on?(date)
    # none of the lodging rooms has a confirmed reservation
    Reservation.includes(:booking)
               .where(
                 date: date,
                 room: rooms.pluck(:id),
                 booking: { status: "confirmed" }
               ).none? && unavailabilities.where(date: date).none?
  end

  def booked_on?(date)
    Reservation.includes(:booking)
               .where(  
                 date: date,
                 room: rooms.pluck(:id),
                 booking: { status: "confirmed" }
               ).exists?
  end

  def form_label
    "#{name} (#{summary})"
  end

  def is_cheveche?
    self.name == "La Chevêche"
  end

  def is_hulotte?
    self.name == "La Hulotte"
  end

  def is_grand_duc?
    self.name == "Le Grand-Duc"
  end
end
