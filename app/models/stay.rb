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

  # Statut de paiement du séjour (epic #26, Phase 1). Le séjour devient l'ancre
  # de paiement ; Booking garde le sien tant que la colonne existe.
  PAYMENT_STATUSES = %w[pending partially_paid paid].freeze

  belongs_to :customer
  has_many :stay_items, dependent: :destroy
  has_many :experience_bookings, dependent: :destroy

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :total_amount_cents

  before_create :generate_activity_token
  before_create :generate_token

  validates :source, inclusion: { in: SOURCES, message: "Canal d'attribution invalide" }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES, message: "Statut de paiement invalide" }
  validates :token, uniqueness: true, allow_nil: true

  scope :current_and_future, -> { where("departure_date >= ?", Date.today).order(arrival_date: :asc) }
  scope :past, -> { where("departure_date < ?", Date.today).order(arrival_date: :desc) }
  scope :from_source, ->(value) { value.present? ? where(source: value) : all }
  scope :recent, -> { order(created_at: :desc) }

  def activity_email_pending?
    activity_email_sent_at.nil? && arrival_date.present? && arrival_date > Date.today
  end

  # The concrete reservable objects attached to this stay (Booking, SpaceBooking, …).
  def bookables
    stay_items.includes(:bookable).map(&:bookable).compact
  end

  # Paiements du séjour. Pendant la transition (issue #26), on unit deux sources :
  #   - le lien direct dénormalisé `payments.stay_id` (nouveau, posé par le
  #     Reservations::Builder et par le backfill de migration) ;
  #   - le lien historique via les items Booking (SpaceBooking n'a pas de Payment
  #     direct — son montant vit dans les colonnes *_amount_cents).
  # L'union garantit l'absence de régression tant que tous les Payment ne sont
  # pas encore reliés directement au Stay.
  def payments
    booking_ids = stay_items.where(bookable_type: "Booking").pluck(:bookable_id)
    Payment.where(stay_id: id).or(Payment.where(booking_id: booking_ids))
  end

  # --- Montant dû / soldé (epic #55, Phase 1) -----------------------------
  # « Soldé » n'est PAS un 4e statut : c'est simplement le statut `paid`
  # existant (epic #26), exprimé ici en euros via des helpers réutilisables.

  # Total effectivement encaissé (paiements au statut `paid`).
  def amount_paid_cents
    payments.paid.sum(:amount_cents)
  end

  # Reste dû = total du séjour − encaissé. Peut être négatif en cas de
  # trop-perçu (remboursement à traiter à la main) ; `settled?` le tolère.
  def amount_due_cents
    total_amount_cents.to_i - amount_paid_cents
  end

  # Séjour soldé : au moins un paiement encaissé ET plus rien à devoir. La
  # condition `amount_paid_cents.positive?` préserve le garde-fou « 0 € sans
  # paiement ne bascule pas en soldé par l'effet de bord d'un 0 >= 0 ».
  def settled?
    amount_paid_cents.positive? && amount_due_cents <= 0
  end

  # Recompute aggregate dates / amount from the attached items (min arrival,
  # max departure, sum of prices). Booking and SpaceBooking both expose
  # from_date/to_date/price_cents.
  # Recalcule le statut de paiement à partir des paiements encaissés. Même
  # sémantique que `Booking#set_payment_status`, à une nuance près : un séjour
  # dont le total est à 0 € et sans paiement reste « pending » (et ne bascule
  # pas en « paid » par l'effet de bord d'un `0 >= 0`).
  def set_payment_status
    status = if settled?
      "paid"
    elsif amount_paid_cents.positive?
      "partially_paid"
    else
      "pending"
    end

    update(payment_status: status)
  end

  def paid?
    payment_status == "paid"
  end

  private

  def generate_activity_token
    loop do
      self.activity_selection_token = SecureRandom.urlsafe_base64(20)
      break unless Stay.exists?(activity_selection_token: activity_selection_token)
    end
  end

  # Jeton public général du séjour — support de la page client /sejour/:token.
  # Distinct de `activity_selection_token` (jeton d'usage unique pour le choix
  # des activités), qu'on ne réutilise pas pour ne pas élargir sa portée.
  def generate_token
    return if token.present?

    loop do
      self.token = SecureRandom.urlsafe_base64(20)
      break unless Stay.unscoped.exists?(token: token)
    end
  end

  public

  def recompute_aggregates!
    items = bookables
    arrivals = items.map { |b| b.try(:from_date) }.compact
    departures = items.map { |b| b.try(:to_date) }.compact
    # Le montant agrège désormais les activités réservées (epic #55, Phase 1) :
    # bookables (hébergement/espaces) + activités ACTIVES (hors annulées). Les
    # DATES restent dérivées des SEULS bookables — une activité ne déborde
    # jamais les bornes du calendrier du séjour.
    amount = items.sum { |b| b.try(:price_cents).to_i } +
             experience_bookings.active.sum(&:price_cents)
    update!(
      arrival_date: arrivals.min,
      departure_date: departures.max,
      total_amount_cents: amount
    )
  end
end
