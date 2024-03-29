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
#  show_on_reports         :boolean          default(TRUE)
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

  def average_booking_duration(start_date, end_date)
    selected_bookings = bookings_for_date_range(start_date, end_date)
    durations = selected_bookings.map do |booking|
      (booking.to_date - booking.from_date).to_i
    end
    (durations.sum / durations.size)
  rescue
    0.0
  end

  def average_booking_people(start_date, end_date)
    selected_bookings = bookings_for_date_range(start_date, end_date)
    people_count = selected_bookings.map do |booking|
      booking.adults + booking.children
    end
    (people_count.sum / people_count.size)
  rescue
    0.0
  end

  def average_booking_revenue(start_date, end_date)
    selected_bookings = bookings_for_date_range(start_date, end_date)
    revenues = selected_bookings.sum(:price_cents)
    if revenues.zero?
      0.0
    else
      (revenues / selected_bookings.count).to_i
    end
  end

  def average_night_revenue(start_date, end_date)
    selected_bookings = bookings_for_date_range(start_date, end_date)
    revenues = selected_bookings.sum(:price_cents)
    if revenues.zero?
      0.0
    else
      nights = selected_bookings.collect { |b| (b.to_date - b.from_date).to_i }.sum
      (revenues / nights).to_i
    end
  end

  def booked_on?(date)
    Reservation.includes(:booking)
               .where(  
                 date: date,
                 room: rooms.pluck(:id),
                 booking: { status: "confirmed" }
               ).exists?
  end

  def bookings_for_date_range(start_date, end_date)
    bookings.where(status: "confirmed", from_date: start_date..end_date)
  end

  def count_bookings(start_date, end_date)
    bookings_for_date_range(start_date, end_date).count
  end

  def count_people(start_date, end_date)
    bookings_for_date_range(start_date, end_date).collect { |b|
      b.adults + b.children
    }.sum
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

  # def occupancy_nights(start_date, end_date)
  #   dates = Reservation.includes(:booking)
  #     .where(date: start_date..end_date, booking: { status: "confirmed", lodging: self })
  #     .pluck(:date).uniq
  # end

  def occupancy_rate(start_date, end_date, opts={})
    days_count = (end_date - start_date + 1).to_i
    dates = Reservation.includes(:booking)
      .where(date: start_date..end_date, booking: { status: "confirmed", lodging: self })
      .pluck(:date).uniq
    if opts[:weekends_only]
      days_count = count_weekend_days(start_date, end_date)
      # filter dates on weekends only (Fridays and Saturdays)
      dates = dates.select do |date|
        date.wday == 5 || date.wday == 6
      end
    end
    (dates.count.to_f / days_count.to_f * 100).to_i
  end

  def revenues(start_date, end_date)
    bookings
      .where(status: "confirmed", from_date: start_date..end_date)
      .sum(:price_cents)
  end

  # Number of occupied beds for a specific period
  def beds_count(start_date, end_date)
    counter = 0
    bookings_for_date_range(start_date, end_date).each do |booking|
      (booking.from_date..booking.to_date - 1).each do |date|
        if (start_date..end_date).cover?(date)
          counter += booking.adults + booking.children
        end
      end
    end
    counter
  end

  private

  def count_weekend_days(start_date, end_date)
    days = 0
    (start_date..end_date).each do |date|
      days += 1 if date.wday == 5 || date.wday == 6
    end
    days
  end
end
