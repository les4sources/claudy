# Pack de journées de coworking (epic #126, Phase 1).
#
# Le coworking n'est PAS un séjour : c'est un domaine indépendant. Un client
# achète un pack de 1/5/10/20 journées, valable 12 mois, et pose ensuite ses
# journées (`CoworkingReservation`) dans la limite de ses crédits.
#
# Le statut de paiement est DÉRIVÉ des `Payment` ancrés sur le pack — le pack ne
# porte aucune colonne de statut, pour qu'il n'y ait jamais deux vérités.
class CoworkingPack < ApplicationRecord
  DAYS_OPTIONS = [1, 5, 10, 20].freeze
  PAYMENT_METHODS = %w[card bank_transfer cash].freeze
  VALIDITY_MONTHS = 12

  belongs_to :customer
  has_many :coworking_reservations, dependent: :destroy
  has_many :payments, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :days_total, inclusion: { in: DAYS_OPTIONS }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :purchased_at, :expires_at, presence: true

  before_validation :set_defaults, on: :create

  scope :ordered, -> { order(purchased_at: :desc) }
  scope :active, -> { where("expires_at >= ?", Time.current) }

  # Journées déjà posées (réservations vivantes — la soft-deletion les retire).
  def days_used = coworking_reservations.count

  def days_remaining = days_total - days_used

  def credits_left? = days_remaining.positive?

  def expired?(on = Date.current)
    expires_at.to_date < on
  end

  # Statut de paiement DÉRIVÉ : "paid" dès que les paiements encaissés couvrent
  # le prix du pack, "pending" s'il existe un paiement en attente, sinon "unpaid".
  def payment_status
    return "paid" if payments.paid.sum(:amount_cents) >= price_cents && price_cents.positive?
    return "paid" if price_cents.zero? && payments.paid.any?
    return "pending" if payments.pending.any?

    "unpaid"
  end

  def paid? = payment_status == "paid"

  # Le paiement par carte est encaissé immédiatement (hors ligne en Phase 1) ;
  # virement et espèces créent un `Payment` en attente à la création du pack.
  def deferred_payment? = payment_method != "card"

  private

  def set_defaults
    self.purchased_at ||= Time.current
    self.expires_at ||= purchased_at + VALIDITY_MONTHS.months
    self.price_cents = Pricing::Catalog.coworking_pack_cents(days_total) if price_cents.to_i.zero?
  end
end
