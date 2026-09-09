# == Schema Information
#
# Table name: experience_bookings
#
#  id                         :bigint           not null, primary key
#  carrier_fee_cents          :integer
#  notes                      :text
#  outcome                    :string
#  outcome_recorded_at        :datetime
#  participants               :integer
#  refusal_reason             :text
#  status                     :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  experience_availability_id :bigint           not null
#  outcome_recorded_by_id     :bigint
#  stay_id                    :bigint           not null
#
# Indexes
#
#  index_experience_bookings_on_experience_availability_id  (experience_availability_id)
#  index_experience_bookings_on_outcome                     (outcome)
#  index_experience_bookings_on_outcome_recorded_by_id      (outcome_recorded_by_id)
#  index_experience_bookings_on_stay_id                     (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (experience_availability_id => experience_availabilities.id)
#  fk_rails_...  (outcome_recorded_by_id => humans.id)
#  fk_rails_...  (stay_id => stays.id)
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

  # La tenue de l'activité (epic #244, phase 2). Confirmée n'est pas tenue :
  # entre les deux il y a le jour J, et parfois personne ne vient. La phase 3
  # ne paiera que ce qui a eu lieu.
  OUTCOMES = %w[held no_show].freeze
  OUTCOME_LABELS = { "held" => "A eu lieu", "no_show" => "N'a pas eu lieu" }.freeze

  # Portée du jeton signé embarqué dans l'email au porteur : il ne vaut QUE
  # pour la validation d'UN `ExperienceBooking` précis (cf. `#validation_token`).
  TOKEN_PURPOSE = :validate_experience_booking
  TOKEN_TTL = 30.days

  # Portée du jeton du rappel de tenue : un jeton de validation ne doit jamais
  # pouvoir servir à déclarer une tenue, ni l'inverse.
  OUTCOME_TOKEN_PURPOSE = :record_experience_booking_outcome
  OUTCOME_TOKEN_TTL = 60.days

  belongs_to :experience_availability
  belongs_to :stay
  belongs_to :outcome_recorded_by, class_name: "Human", optional: true

  # Audit (epic #81) : seul modèle rapatrié par la fusion de séjours qui n'avait
  # pas encore d'historique (Stay/StayItem/MealOrder/Payment l'ont déjà). Un
  # changement de `stay_id` (rattachement à un autre séjour) est ainsi tracé.
  # Table `versions` par défaut (PK bigint compatible, contrairement à Payment).
  has_paper_trail

  delegate :experience, to: :experience_availability

  # L'équipe garde la main : depuis l'admin, on peut ajouter une place de plus en
  # connaissance de cause (décision Michael 2026-08-21). Les canaux CLIENT — le
  # funnel et le rail email — n'y touchent pas et restent bornés.
  attr_accessor :capacity_override

  before_save :freeze_carrier_fee

  validates :participants, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  # Un refus n'existe jamais sans motif — c'est l'information que le client
  # reçoit et qui justifie l'invitation à re-choisir un créneau.
  validates :refusal_reason, presence: true, if: :refused?
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validate :participants_fit_in_availability

  before_validation :set_default_status

  # Une activité `refused` est morte au même titre qu'une `cancelled` : elle ne
  # compte ni dans le montant du séjour (Phase 1) ni dans les listings actifs.
  scope :active, -> { where.not(status: %w[cancelled refused]) }
  scope :pending,   -> { where(status: "pending") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :refused,   -> { where(status: "refused") }

  # Ce qui attend une réponse « ça a eu lieu ? » : confirmée, passée, sans
  # verdict. C'est la file de travail de l'écran « À confirmer » et du rappel.
  scope :awaiting_outcome, -> {
    confirmed.where(outcome: nil)
             .joins(:experience_availability)
             .where(experience_availabilities: { available_on: ...Date.current })
  }
  scope :held, -> { where(outcome: "held") }

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

  def held?   = outcome == "held"
  def no_show? = outcome == "no_show"
  def outcome_recorded? = outcome.present?
  def outcome_label = OUTCOMES.include?(outcome) ? OUTCOME_LABELS.fetch(outcome) : nil

  # Réservations visibles/actionnables par un utilisateur : tout pour un admin
  # global (staff sans activité rattachée), seulement les siennes pour un
  # porteur. Centralisé ici pour que contrôleur admin ET canal jeton partagent
  # exactement la même règle de scoping.
  def self.for_user(user)
    base = with_visible_stay
    return base if user.nil? || user.global_admin?

    base.for_carrier(user.human)
  end

  # Un séjour peut disparaître en laissant ses activités derrière lui : son
  # `deleted_at` est alors posé sans que le `dependent: :destroy` ne joue (c'est
  # le cas de trois réservations en production ; `Stay#destroy`, lui, les emporte
  # bien). Le `default_scope` de `soft_deletion` rend ensuite `booking.stay` nil,
  # et la page de validation — qui affiche le client du séjour — plantait en 500
  # pour TOUS les porteurs à cause d'une seule réservation orpheline.
  # Le `joins` hérite du `default_scope` de `Stay` : les orphelines sortent de
  # toutes les portées admin — invisibles à l'index, 404 sur une action ciblée.
  scope :with_visible_stay, -> { joins(:stay) }

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

  # Transition pending → confirmed (validation du porteur). Le montant dû au
  # porteur se fige tout seul, par le callback ci-dessous — il n'y a donc pas
  # deux chemins à tenir à jour (validation porteur ET création admin en
  # `confirmed`), ce qui est exactement la façon dont un montant finit par
  # manquer sur l'un des deux.
  def confirm!
    update!(status: "confirmed")
  end

  # --- Rémunération du porteur (epic #244, phase 1) ---

  # Le montant est FIGÉ au moment de la confirmation (décision 2), au tarif en
  # vigueur à la DATE DU CRÉNEAU : un changement de barème ultérieur ne réécrit
  # jamais le passé. Un montant déjà posé n'est pas recalculé.
  def freeze_carrier_fee
    return unless confirmed?
    return if carrier_fee_cents.present?

    self.carrier_fee_cents = computed_carrier_fee_cents
  end

  # Ce que la prestation vaudrait, au tarif de la date de son créneau. nil quand
  # l'activité n'a pas de durée : sans durée, pas de rémunération calculable —
  # l'écran le dit et propose de compléter la durée.
  def computed_carrier_fee_cents
    experience&.carrier_fee_cents_on(experience_availability&.available_on)
  end

  # Confirmée mais sans montant : l'activité n'a pas de durée en heures. C'est
  # le seul cas, et c'est réparable en une saisie.
  def carrier_fee_missing? = confirmed? && carrier_fee_cents.nil?

  # Transition pending → refused. La raison est obligatoire : un motif vide
  # déclenche une `RecordInvalid` (la validation modèle fait foi).
  def refuse!(reason)
    update!(status: "refused", refusal_reason: reason)
  end

  # --- Tenue de l'activité (epic #244, phase 2) ---

  class OutcomeNotRecordable < StandardError; end

  def mark_held!(by: nil) = record_outcome!("held", by: by)
  def mark_no_show!(by: nil) = record_outcome!("no_show", by: by)

  # Deux gardes, et les deux comptent.
  #
  # Une réservation NON CONFIRMÉE n'a rien à tenir : une `pending` attend encore
  # le porteur, une `refused` ou une `cancelled` est morte. Déclarer leur tenue
  # les ferait entrer dans le relevé de rémunération par une porte dérobée.
  #
  # Un créneau À VENIR ne peut pas avoir eu lieu. Sans cette garde, un porteur
  # pressé solderait sa saison en janvier — et le relevé paierait des heures que
  # personne n'a faites.
  def record_outcome!(value, by: nil)
    raise ArgumentError, "Verdict inconnu : #{value}" unless OUTCOMES.include?(value.to_s)

    unless confirmed?
      raise OutcomeNotRecordable,
            "Seule une activité confirmée peut être déclarée tenue ou non tenue."
    end
    if slot_in_the_future?
      raise OutcomeNotRecordable,
            "Ce créneau n'a pas encore eu lieu — reviens après le #{I18n.l(slot_date, format: :long)}."
    end

    update!(outcome: value.to_s, outcome_recorded_at: Time.current, outcome_recorded_by: by)
  end

  def slot_date = experience_availability&.available_on

  def slot_in_the_future? = slot_date.blank? || slot_date >= Date.current

  # Jeton du rappel de tenue — portée et durée propres, distinctes de celles du
  # jeton de validation.
  def outcome_token
    signed_id(purpose: OUTCOME_TOKEN_PURPOSE, expires_in: OUTCOME_TOKEN_TTL)
  end

  def self.find_by_outcome_token(token)
    find_signed(token, purpose: OUTCOME_TOKEN_PURPOSE)
  end

  # Montant TVAC de l'activité réservée (epic #55, Phase 1). Délègue au service
  # `Pricing::ExperienceLine`, source de vérité unique du barème « forfait fixe
  # + €/pers ». `experience` est délégué depuis `experience_availability`.
  def price_cents
    Pricing::ExperienceLine.amount_cents(experience, participants: participants)
  end

  private

  # Un créneau sans capacité déclarée n'en borne aucune. Sinon on refuse ce qui
  # dépasse — c'est ce qui ferme la course entre deux clients qui visent la
  # dernière place, là où le funnel se contentait de masquer les créneaux pleins
  # à l'affichage. Une réservation morte (annulée, refusée) ne bloque personne, et
  # l'édition ne se compte pas elle-même.
  def participants_fit_in_availability
    return if capacity_override
    return if experience_availability.blank? || participants.to_i <= 0
    return if cancelled? || refused?

    spots = experience_availability.available_spots(ignoring: id)
    return if spots.nil? || participants.to_i <= spots

    errors.add(:participants,
               spots.zero? ? "— ce créneau est complet" : "— il ne reste que #{spots} place(s) sur ce créneau")
  end

  def set_default_status
    self.status ||= "pending"
  end
end
