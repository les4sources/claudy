# == Schema Information
#
# Table name: hamac_bookings
#
#  id          :bigint           not null, primary key
#  firstname   :string
#  lastname    :string
#  email       :string
#  phone       :string
#  group_name  :string
#  from_date   :date
#  to_date     :date
#  kind        :string           default("simple"), not null
#  count       :integer          default(1), not null
#  status      :string
#  price_cents :integer
#  token       :string
#  notes       :text
#  deleted_at  :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Location de HAMACS sur un séjour (issue #138). Jusqu'ici les hamacs n'existaient
# que dans le devis (`Reservations::Draft#hamacs`, lignes `PricingModel`) : un
# séjour avec hamacs payés ne les montrait ni en modale ni au calendrier, et rien
# n'empêchait de sur-louer. Ce modèle les persiste HONNÊTEMENT, sur le pattern
# camping/van par nuit : une réservation par PLAGE CONTIGUË de valeur constante,
# fenêtre `[from_date, to_date)`, rattachée au séjour par un `StayItem` polymorphe.
#
# Différence avec camping/van : la capacité n'est PAS une constante du domaine
# mais le STOCK physique du `RentalItem` correspondant (« Hamac simple » /
# « Hamac double », colonne `stock`). Stock non renseigné (nil) = aucune limite —
# on ne bloque jamais une réservation sur une donnée de catalogue absente.
class HamacBooking < ApplicationRecord
  KINDS = %w[simple double].freeze

  # Nom du `RentalItem` porteur du stock ET du tarif de chaque type de hamac.
  # Même table de correspondance que `Pricing::Catalog.hamac_rate`.
  RENTAL_ITEM_NAMES = { "simple" => "Hamac simple", "double" => "Hamac double" }.freeze

  LABELS = { "simple" => "Hamac simple", "double" => "Hamac double" }.freeze

  # Inverse de la relation StayItem (mêmes conventions que CampingBooking).
  has_one :stay_item, as: :bookable
  has_one :stay, through: :stay_item

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents, allow_nil: true

  validates :kind, inclusion: { in: KINDS }
  validates :count, numericality: { only_integer: true, greater_than: 0 }

  before_create :generate_token

  scope :confirmed, -> { where(status: "confirmed") }
  # Réservations couvrant la nuit `date` (from <= date < to) — même convention
  # `[from, to)` que `GlobalCapacityBookable`.
  scope :covering, ->(date) { where("from_date <= ? AND to_date > ?", date, date) }
  scope :of_kind, ->(kind) { where(kind: kind.to_s) }
  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }

  class << self
    # Stock total de ce type de hamac = `RentalItem#stock`. nil quand l'article
    # n'existe pas ou que son stock n'est pas renseigné → capacité non bornée.
    def total_stock(kind)
      RentalItem.find_by(name: RENTAL_ITEM_NAMES[kind.to_s])&.stock
    end

    # Unités déjà CONFIRMÉES pour la nuit `date` (toutes réservations vivantes
    # confondues), en excluant éventuellement des réservations données (édition).
    def units_reserved_on(kind, date, excluding_id: nil)
      scope = of_kind(kind).confirmed.covering(date)
      scope = scope.where.not(id: excluding_id) if excluding_id.present?
      scope.sum(:count)
    end

    def remaining_on(kind, date, excluding_id: nil)
      stock = total_stock(kind)
      return nil if stock.nil?
      [stock - units_reserved_on(kind, date, excluding_id: excluding_id), 0].max
    end

    # Première nuit en rupture de stock pour une demande, ou nil si tout passe
    # (y compris quand le stock n'est pas renseigné).
    def capacity_conflict_date(kind:, units:, from:, to:, excluding_id: nil)
      stock = total_stock(kind)
      return nil if stock.nil? || units.to_i < 1 || from.blank? || to.blank?

      (from...to).find do |date|
        units_reserved_on(kind, date, excluding_id: excluding_id) + units.to_i > stock
      end
    end

    def label_for(kind)
      LABELS.fetch(kind.to_s, "Hamac")
    end
  end

  def confirmed? = status == "confirmed"
  def pending?   = status == "pending"

  def label = self.class.label_for(kind)

  def name = "#{firstname} #{lastname}".strip

  def generate_token
    return if token.present?
    loop do
      self.token = SecureRandom.hex(8)
      break unless HamacBooking.unscoped.exists?(token: token)
    end
  end
end
