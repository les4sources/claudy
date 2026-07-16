# == Schema Information
#
# Table name: experience_bookings
#
#  id                          :bigint           not null, primary key
#  experience_availability_id  :bigint           not null
#  stay_id                     :bigint           not null
#  participants                :integer
#  status                      :string           default("pending")
#  notes                       :text
#  refusal_reason              :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
class ExperienceBooking < ApplicationRecord
  # `refused` (epic #55, Phase 2) : le porteur de l'activité a décliné le
  # créneau demandé. Un refus porte TOUJOURS une raison (cf. validation).
  STATUSES = %w[pending confirmed refused cancelled].freeze

  # Statuts que l'admin peut POSER à la création d'une activité (epic #55,
  # Phase 6) : soit `pending` (à valider par le porteur — flux Phase 2), soit
  # `confirmed` (déjà validé — court-circuite la validation). On ne crée jamais
  # directement un `refused` (raison obligatoire, flux dédié) ni un `cancelled`.
  ADMIN_CREATABLE_STATUSES = %w[pending confirmed].freeze

  # Portée du jeton signé embarqué dans l'email au porteur : il ne vaut QUE
  # pour la validation d'UN `ExperienceBooking` précis (cf. `#validation_token`).
  TOKEN_PURPOSE = :validate_experience_booking
  TOKEN_TTL = 30.days

  belongs_to :experience_availability
  belongs_to :stay

  delegate :experience, to: :experience_availability

  validates :participants, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  # Un refus n'existe jamais sans motif — c'est l'information que le client
  # reçoit et qui justifie l'invitation à re-choisir un créneau.
  validates :refusal_reason, presence: true, if: :refused?

  before_validation :set_default_status

  # Une activité `refused` est morte au même titre qu'une `cancelled` : elle ne
  # compte ni dans le montant du séjour (Phase 1) ni dans les listings actifs.
  scope :active, -> { where.not(status: %w[cancelled refused]) }
  scope :pending,   -> { where(status: "pending") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :refused,   -> { where(status: "refused") }

  # Réservations rattachées aux activités d'un porteur donné (via
  # `experience.human`). Base du scoping d'autorisation du canal admin.
  scope :for_carrier, ->(human) {
    joins(experience_availability: :experience)
      .where(experiences: { human_id: human.id })
  }

  def pending?   = status == "pending"
  def confirmed? = status == "confirmed"
  def refused?   = status == "refused"
  def cancelled? = status == "cancelled"

  # Réservations visibles/actionnables par un utilisateur : tout pour un admin
  # global (staff sans activité rattachée), seulement les siennes pour un
  # porteur. Centralisé ici pour que contrôleur admin ET canal jeton partagent
  # exactement la même règle de scoping.
  def self.for_user(user)
    return all if user.nil? || user.global_admin?

    for_carrier(user.human)
  end

  # Jeton signé, à portée d'UN seul `ExperienceBooking` et à durée limitée,
  # transporté dans le lien de l'email au porteur. On s'appuie sur `signed_id`
  # de Rails (HMAC + purpose) : impossible de le forger ou de le rejouer pour
  # un autre enregistrement / une autre action.
  def validation_token
    signed_id(purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
  end

  # Résout un jeton en `ExperienceBooking`. Renvoie nil si le jeton est
  # invalide, expiré, ou émis pour une autre portée — jamais d'exception.
  def self.find_by_validation_token(token)
    find_signed(token, purpose: TOKEN_PURPOSE)
  end

  # Transition pending → confirmed (validation du porteur).
  def confirm!
    update!(status: "confirmed")
  end

  # Transition pending → refused. La raison est obligatoire : un motif vide
  # déclenche une `RecordInvalid` (la validation modèle fait foi).
  def refuse!(reason)
    update!(status: "refused", refusal_reason: reason)
  end

  # Montant TVAC de l'activité réservée (epic #55, Phase 1). Délègue au service
  # `Pricing::ExperienceLine`, source de vérité unique du barème « forfait fixe
  # + €/pers ». `experience` est délégué depuis `experience_availability`.
  def price_cents
    Pricing::ExperienceLine.amount_cents(experience, participants: participants)
  end

  private

  def set_default_status
    self.status ||= "pending"
  end
end
