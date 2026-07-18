# == Schema Information
#
# Table name: van_bookings
#
#  id          :bigint           not null, primary key
#  firstname   :string
#  lastname    :string
#  email       :string
#  phone       :string
#  group_name  :string
#  from_date   :date
#  to_date     :date
#  vehicles    :integer          default(1), not null
#  status      :string
#  price_cents :integer
#  token       :string
#  notes       :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Réservation de VAN / camping-car — epic #66, Phase 3. Même logique que le
# camping : occupe le calendrier via un `StayItem` polymorphe et consomme
# `vehicles` véhicules contre une CAPACITÉ GLOBALE (nombre de places véhicules du
# domaine). Tarif forfait/nuit/véhicule (`Pricing::Catalog::VAN_PER_NIGHT_CENTS`).
class VanBooking < ApplicationRecord
  include GlobalCapacityBookable

  # Capacité totale en VÉHICULES. Valeur par défaut provisoire — À AJUSTER par
  # Michael selon le nombre réel de places véhicules du domaine.
  TOTAL_CAPACITY = 5

  has_one :stay_item, as: :bookable
  has_one :stay, through: :stay_item

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true

  validates :vehicles, numericality: { only_integer: true, greater_than: 0 }

  before_create :generate_token

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  def self.capacity_units_column = :vehicles

  def capacity_units = vehicles.to_i

  def confirmed? = status == "confirmed"
  def pending?   = status == "pending"

  def name = "#{firstname} #{lastname}".strip

  def generate_token
    return if token.present?
    loop do
      self.token = SecureRandom.hex(8)
      break unless VanBooking.unscoped.exists?(token: token)
    end
  end
end
