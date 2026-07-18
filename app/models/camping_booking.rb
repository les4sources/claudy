# == Schema Information
#
# Table name: camping_bookings
#
#  id          :bigint           not null, primary key
#  firstname   :string
#  lastname    :string
#  email       :string
#  phone       :string
#  group_name  :string
#  from_date   :date
#  to_date     :date
#  people      :integer          default(1), not null
#  kind        :string           default("tente"), not null
#  status      :string
#  price_cents :integer
#  token       :string
#  notes       :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Réservation de CAMPING (tente) — epic #66, Phase 3. Occupe le calendrier via un
# `StayItem` polymorphe (expose from_date/to_date comme Booking/SpaceBooking), et
# consomme `people` personnes contre la CAPACITÉ GLOBALE du terrain (pas
# d'emplacements nommés — décision figée). Tarif €/pers/nuit (`Pricing::Catalog`).
class CampingBooking < ApplicationRecord
  include GlobalCapacityBookable

  # Capacité totale du terrain de camping, en PERSONNES. Valeur par défaut
  # provisoire — À AJUSTER par Michael selon la capacité réelle du domaine.
  TOTAL_CAPACITY = 30

  # Inverse de la relation StayItem (mêmes conventions que Booking/SpaceBooking).
  has_one :stay_item, as: :bookable
  has_one :stay, through: :stay_item

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true

  validates :people, numericality: { only_integer: true, greater_than: 0 }

  before_create :generate_token

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  def self.capacity_units_column = :people

  # Unités consommées par cette réservation (contrat GlobalCapacityBookable).
  def capacity_units = people.to_i

  def confirmed? = status == "confirmed"
  def pending?   = status == "pending"

  def name = "#{firstname} #{lastname}".strip

  def generate_token
    return if token.present?
    loop do
      self.token = SecureRandom.hex(8)
      break unless CampingBooking.unscoped.exists?(token: token)
    end
  end
end
