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
#  available_for_bookings  :boolean
#
class Lodging < ApplicationRecord
  has_many :lodging_rooms
  has_many :rooms, through: :lodging_rooms
  has_many :bookings
  has_many :unavailabilities

  # Self-referential composition (Le Grand-Duc = La Hulotte + La Chevêche).
  # A composite lodging is made of component lodgings; reserving the composite
  # makes its components unavailable and vice-versa — derived on the fly, never
  # stored, never mirrored into a duplicate reservation (decision §11.4 / AC-51).
  has_many :lodging_compositions,
           foreign_key: :composite_lodging_id,
           class_name: "LodgingComposition",
           dependent: :destroy
  has_many :composed_of_lodgings,
           through: :lodging_compositions,
           source: :component_lodging
  has_many :component_memberships,
           foreign_key: :component_lodging_id,
           class_name: "LodgingComposition",
           dependent: :destroy
  has_many :part_of_lodgings,
           through: :component_memberships,
           source: :composite_lodging

  monetize :price_night_cents

  has_soft_deletion default_scope: true

  def composite?
    composed_of_lodgings.any?
  end

  def component?
    part_of_lodgings.any?
  end

  # Availability that accounts for the composition. The lodging is available only
  # if its OWN rooms are free AND every lodging entangled with it (its components
  # if it is a composite, its composites if it is a component) is also free on
  # its own rooms. This makes Grand-Duc availability a pure read-derivation of
  # Hulotte + Chevêche, with no stored blocking and no mirror booking.
  def available_between?(from_date, to_date)
    entangled_lodgings_including_self.all? do |lodging|
      lodging.self_available_between?(from_date, to_date)
    end
  end

  def available_on?(date)
    available_between?(date, date)
  end

  # Availability of THIS lodging's own rooms only (legacy behaviour, composition
  # blind). Kept public so the composition logic and any caller that explicitly
  # wants the physical-unit answer can reach it; behaviour for non-composed
  # lodgings is identical to the previous available_between?/available_on?.
  def self_available_between?(from_date, to_date)
    Reservation.includes(:booking)
               .where(
                 date: from_date..to_date,
                 room: rooms.pluck(:id),
                 booking: { status: "confirmed" }
               ).none? && unavailabilities.where(date: from_date..to_date).none?
  end

  def self_available_on?(date)
    self_available_between?(date, date)
  end

  # The set of lodgings whose occupancy entangles with this one (self + its
  # components if composite, self + its composites if component).
  def entangled_lodgings_including_self
    ([self] + composed_of_lodgings.to_a + part_of_lodgings.to_a).uniq
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

  def is_tiny?
    self.name == "Tiny house"
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
  def occupied_beds_count(start_date, end_date)
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

  def beds_average_value(start_date, end_date)
    value = 0
    nights = 0
    bookings_for_date_range(start_date, end_date).each do |booking|
      (booking.from_date..booking.to_date - 1).each do |date|
        if (start_date..end_date).cover?(date)
          nights += 1
          value += booking.price_cents / booking.nights_count / booking.beds_count
        end
      end
    end
    if value > 0 && nights > 0
      value.to_f / nights.to_f
    else
      0.0
    end
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
