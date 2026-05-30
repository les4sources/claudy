# == Schema Information
#
# Table name: stays
#
#  id                 :bigint           not null, primary key
#  customer_id        :bigint           not null
#  arrival_date       :date
#  departure_date     :date
#  status             :string
#  total_amount_cents :integer          default(0), not null
#  notes              :text
#  legacy_origin      :string
#  deleted_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Stay < ApplicationRecord
  # Canal d'attribution (Q9 / AC-T2-22). DISTINCT de `legacy_origin` (clé
  # d'import/dédup de la migration legacy). Tout Stay créé via /reservation
  # porte la valeur par défaut "reservation".
  SOURCES = %w[reservation tally_legacy ota manual].freeze

  belongs_to :customer
  has_many :stay_items, dependent: :destroy

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :total_amount_cents

  validates :source, inclusion: { in: SOURCES, message: "Canal d'attribution invalide" }

  scope :current_and_future, -> { where("departure_date >= ?", Date.today).order(arrival_date: :asc) }
  scope :past, -> { where("departure_date < ?", Date.today).order(arrival_date: :desc) }
  scope :from_source, ->(value) { value.present? ? where(source: value) : all }
  scope :recent, -> { order(created_at: :desc) }

  # The concrete reservable objects attached to this stay (Booking, SpaceBooking, …).
  def bookables
    stay_items.includes(:bookable).map(&:bookable).compact
  end

  # Read-derived payments: walk through the Booking items only (SpaceBooking has
  # no Payment association — its money lives in *_amount_cents columns). Schema
  # of `payments` is untouched (decision §11.6).
  def payments
    booking_ids = stay_items.where(bookable_type: "Booking").pluck(:bookable_id)
    return Payment.none if booking_ids.empty?
    Payment.where(booking_id: booking_ids)
  end

  # Recompute aggregate dates / amount from the attached items (min arrival,
  # max departure, sum of prices). Booking and SpaceBooking both expose
  # from_date/to_date/price_cents.
  def recompute_aggregates!
    items = bookables
    arrivals = items.map { |b| b.try(:from_date) }.compact
    departures = items.map { |b| b.try(:to_date) }.compact
    amount = items.sum { |b| b.try(:price_cents).to_i }
    update!(
      arrival_date: arrivals.min,
      departure_date: departures.max,
      total_amount_cents: amount
    )
  end
end
