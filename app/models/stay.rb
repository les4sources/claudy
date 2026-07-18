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

  # Statuts qu'un admin peut POSER à la création d'un séjour (epic #66, Phase 1).
  # `status` reste une chaîne libre au niveau modèle (valeurs historiques :
  # pending / confirmed / canceled) ; on borne seulement ce que le CRUD admin
  # accepte de créer — jamais un `canceled` par le formulaire de création.
  STATUSES_ADMIN_CREATABLE = %w[pending confirmed].freeze

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
  # Adossé au TOTAL PRÉVU (activités pending incluses) : « tout est couvert, y
  # compris ce qui reste à valider ». Le STATUT de paiement, lui, s'appuie sur
  # l'EXIGIBLE (voir plus bas / `set_payment_status`).
  def settled?
    amount_paid_cents.positive? && amount_due_cents <= 0
  end

  # --- Total prévu vs montant exigible (epic #55, Phase 3) ----------------
  # Deux notions DISTINCTES cohabitent, à ne pas confondre :
  #
  #   • « TOTAL PRÉVU » = `total_amount_cents` = hébergement/espaces + activités
  #     ACTIVES (pending + confirmed). Ce que le séjour coûtera si tout est
  #     validé. Sémantique Phase 1 — `amount_due_cents` et `settled?` s'y adossent
  #     et restent inchangés.
  #
  #   • « EXIGIBLE » (payable now) = ce que le client peut/doit régler MAINTENANT
  #     = total prévu MOINS les activités encore `pending` (pas encore validées
  #     par le porteur, donc non facturables). On l'exprime comme un DELTA du
  #     total prévu — et non recalculé depuis les bookables — pour rester
  #     rigoureusement cohérent avec `total_amount_cents` en toute circonstance
  #     (y compris un séjour dont le total a été posé directement, sans items).
  #
  # `price_cents` d'une activité est CALCULÉ (délègue au barème Pricing) : on
  # somme donc en Ruby (bloc), jamais en SQL — comme `recompute_aggregates!`.

  # Activités en attente de validation — NON exigibles.
  def experiences_pending_amount_cents
    experience_bookings.pending.sum(&:price_cents)
  end

  # Activités validées par le porteur — exigibles.
  def experiences_confirmed_amount_cents
    experience_bookings.confirmed.sum(&:price_cents)
  end

  # Part hébergement/espaces (bookables) = total prévu − activités actives.
  def lodging_and_spaces_amount_cents
    total_amount_cents.to_i -
      experiences_confirmed_amount_cents -
      experiences_pending_amount_cents
  end

  # Assiette EXIGIBLE = hébergement/espaces + activités CONFIRMED
  #                   = total prévu − activités pending.
  def payable_amount_cents
    total_amount_cents.to_i - experiences_pending_amount_cents
  end

  # Reste dû EXIGIBLE = assiette exigible − encaissé. Peut être négatif en cas
  # de trop-perçu ; le bouton « Payer le solde » ne s'affiche que s'il est > 0.
  def balance_due_cents
    payable_amount_cents - amount_paid_cents
  end

  # Reste-t-il un solde exigible à encaisser maintenant ?
  def payable_now?
    balance_due_cents.positive?
  end

  # Recompute aggregate dates / amount from the attached items (min arrival,
  # max departure, sum of prices). Booking and SpaceBooking both expose
  # from_date/to_date/price_cents.
  # Recalcule le statut de paiement à partir des paiements encaissés. Il s'adosse
  # à l'EXIGIBLE (`balance_due_cents`) et NON au total prévu : un séjour dont les
  # seules dettes restantes sont des activités `pending` (non validées, donc non
  # facturables) est « paid » dès que l'exigible est couvert (epic #55, Phase 3).
  # Le garde-fou Phase 1 tient toujours : un séjour à 0 € sans paiement reste
  # « pending » (pas de bascule par effet de bord d'un `0 >= 0`).
  # NB : sans activité `pending`, `balance_due_cents == amount_due_cents` — le
  # comportement est donc identique à la Phase 1 pour tous les séjours existants.
  def set_payment_status
    status = if amount_paid_cents.positive? && balance_due_cents <= 0
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
    # Séjour SANS hébergement (epic #66, Phase 2) : les dates viennent des
    # SpaceBooking (Booking ET SpaceBooking exposent from_date/to_date), donc un
    # séjour « espaces seuls » reste daté. On ne réécrit les dates QUE si au moins
    # un bookable en porte — sinon on préserve les dates existantes plutôt que de
    # les écraser à nil (garde-fou : un recompute sur un séjour sans bookable daté
    # ne doit pas effacer arrival/departure).
    attrs = { total_amount_cents: amount }
    attrs[:arrival_date]   = arrivals.min   if arrivals.any?
    attrs[:departure_date] = departures.max if departures.any?
    update!(attrs)
  end
end
