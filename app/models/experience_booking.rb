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
#  performed_by_id            :bigint
#  stay_id                    :bigint           not null
#
# Indexes
#
#  index_experience_bookings_on_experience_availability_id  (experience_availability_id)
#  index_experience_bookings_on_outcome                     (outcome)
#  index_experience_bookings_on_outcome_recorded_by_id      (outcome_recorded_by_id)
#  index_experience_bookings_on_performed_by_id             (performed_by_id)
#  index_experience_bookings_on_stay_id                     (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (experience_availability_id => experience_availabilities.id)
#  fk_rails_...  (outcome_recorded_by_id => humans.id)
#  fk_rails_...  (performed_by_id => humans.id)
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

  # Libellés de statut, en français. Ils n'existaient pas : les vues affichaient
  # `status` brut en repli (« confirmed » sur une fiche autrement francophone).
  STATUS_LABELS = { "pending" => "À valider", "confirmed" => "Confirmée",
                    "refused" => "Refusée", "cancelled" => "Annulée" }.freeze

  # Portée du jeton signé embarqué dans l'email au porteur : il ne vaut QUE
  # pour la validation d'UN `ExperienceBooking` précis (cf. `#validation_token`).
  TOKEN_PURPOSE = :validate_experience_booking
  TOKEN_TTL = 30.days

  # Portée du jeton du rappel de tenue : un jeton de validation ne doit jamais
  # pouvoir servir à déclarer une tenue, ni l'inverse.
  OUTCOME_TOKEN_PURPOSE = :record_experience_booking_outcome
  OUTCOME_TOKEN_TTL = 60.days

  # Commentable (epic #242, phase 4) : ce qui s'échange entre l'équipe et le
  # porteur au sujet d'un créneau — un horaire à décaler, un participant de plus.
  include Commentable

  belongs_to :experience_availability
  belongs_to :stay
  belongs_to :outcome_recorded_by, class_name: "Human", optional: true
  # Qui a TENU la prestation, quand ce n'est pas le porteur de l'activité
  # (Michael, 2026-10-13 : « il y a un porteur principal, mais d'autres
  # personnes peuvent faire la prestation »). C'est lui qu'on rémunère.
  belongs_to :performed_by, class_name: "Human", optional: true

  # Audit (epic #81) : seul modèle rapatrié par la fusion de séjours qui n'avait
  # pas encore d'historique (Stay/StayItem/MealOrder/Payment l'ont déjà). Un
  # changement de `stay_id` (rattachement à un autre séjour) est ainsi tracé.
  # Table `versions` par défaut (PK bigint compatible, contrairement à Payment).
  has_paper_trail

  delegate :experience, to: :experience_availability

  def status_label = STATUS_LABELS[status.to_s] || status.to_s

  # Celui qui tient la prestation : la personne nommée sur la réservation, sinon
  # le porteur de l'activité. C'est lui qu'une question concerne et lui que le
  # relevé paie. `Experience#human` peut être absent (activité orpheline) — on
  # ne prévient alors personne plutôt que de prévenir au hasard.
  def carrier = performed_by || experience&.human

  def comment_recipients
    [carrier&.user].compact
  end

  def comment_label
    name = experience&.name.presence || "l'activité"
    date = experience_availability&.available_on
    date ? "#{name} du #{I18n.l(date, format: :long)}" : name
  end

  # L'équipe garde la main : depuis l'admin, on peut ajouter une place de plus en
  # connaissance de cause (décision Michael 2026-08-21). Les canaux CLIENT — le
  # funnel et le rail email — n'y touchent pas et restent bornés.
  attr_accessor :capacity_override

  # RELEVÉE = FIGÉE (epic #244, phase 3). Une prestation portée sur un relevé a
  # été payée, ou est sur le point de l'être : changer son verdict après coup
  # rendrait le relevé faux sans que rien ne le dise. La correction passe par
  # une contre-passation du relevé.
  has_one :carrier_statement_line, dependent: :restrict_with_error
  has_one :carrier_statement, through: :carrier_statement_line

  validate :outcome_frozen_once_reported
  validate :payout_frozen_once_reported

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

  # Réservations qu'un porteur TIENT : celles où il est nommé, et celles de ses
  # activités où personne d'autre ne l'est. C'est ce qu'un relevé lui paie.
  scope :for_carrier, ->(human) {
    joins(experience_availability: :experience)
      .where("COALESCE(experience_bookings.performed_by_id, experiences.human_id) = ?", human.id)
  }

  # Réservations qu'un porteur VOIT : toutes celles de ses activités (il les
  # valide, même quand quelqu'un d'autre les tient) et celles qu'il tient
  # ailleurs. Base du scoping d'autorisation du canal admin.
  scope :visible_to_carrier, ->(human) {
    joins(experience_availability: :experience)
      .where("experiences.human_id = :id OR experience_bookings.performed_by_id = :id", id: human.id)
  }

  # Toutes les personnes qu'un relevé peut payer : les porteurs des activités et
  # celles qui ont tenu une prestation à leur place.
  def self.carriers
    Human.where(id: Experience.where.not(human_id: nil).select(:human_id))
         .or(Human.where(id: where.not(performed_by_id: nil).select(:performed_by_id)))
  end

  def pending?   = status == "pending"
  def confirmed? = status == "confirmed"
  def refused?   = status == "refused"
  def cancelled? = status == "cancelled"

  def held?   = outcome == "held"
  def no_show? = outcome == "no_show"
  def outcome_recorded? = outcome.present?
  def outcome_label = OUTCOMES.include?(outcome) ? OUTCOME_LABELS.fetch(outcome) : nil

  # Réservations visibles/actionnables par un utilisateur : tout pour l'équipe
  # et l'accueil, seulement les siennes pour un compte « accès restreint aux
  # activités » (cf. `User#restricted_to_own_activities?`). Centralisé ici pour
  # que contrôleur admin ET canal jeton partagent exactement la même règle.
  # Un compte restreint sans membre (ou dont le membre est désactivé) ne voit
  # rien : fail-closed.
  def self.for_user(user)
    base = with_visible_stay
    return base if user.nil? || !user.restricted_to_own_activities?
    return base.none if user.human.nil?

    base.visible_to_carrier(user.human)
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

  # Le montant se corrige à la main (une prestation de 4 h sur une activité
  # d'une heure, un tarif convenu à part) : saisi en EUROS, virgule acceptée.
  # Vider le champ rend la main au calcul, à la prochaine sauvegarde confirmée.
  def carrier_fee
    carrier_fee_cents.present? ? carrier_fee_cents / 100.0 : nil
  end

  def carrier_fee=(value)
    raw = value.to_s.strip.tr(",", ".")
    self.carrier_fee_cents = raw.blank? ? nil : (raw.to_f * 100).round
  end

  # Transition pending → refused. La raison est obligatoire : un motif vide
  # déclenche une `RecordInvalid` (la validation modèle fait foi).
  def refuse!(reason)
    update!(status: "refused", refusal_reason: reason)
  end

  # --- Rétablir une activité retirée (Michael, 2026-10-19) ---

  class NotRestorable < StandardError; end

  # « Retirer » une activité ne la supprime pas : elle passe en `cancelled`. Une
  # activité retirée par erreur (cas du séjour #1518 : les ânes, tenus et déjà
  # payés à Béné, retirés après coup) revient au statut qu'elle avait avant le
  # retrait. La recréer paierait le porteur une seconde fois. Aucun email : le
  # client a déjà reçu ce qu'il devait recevoir à l'époque.
  def restore!
    raise NotRestorable, "Seule une activité retirée se rétablit (celle-ci est #{status_label.downcase})." unless cancelled?

    self.capacity_override = true
    update!(status: status_before_cancellation)
  end

  # Le statut d'avant le retrait, d'après l'historique. Sans trace, une
  # activité tenue ou déjà rémunérée était forcément confirmée ; sinon, elle
  # repart à valider plutôt que d'entrer d'office dans le solde.
  def status_before_cancellation
    versions.reorder(created_at: :desc, id: :desc).each do |version|
      from, to = version.changeset["status"]
      return from if to == "cancelled" && ADMIN_CREATABLE_STATUSES.include?(from)
    end
    outcome.present? || carrier_fee_cents.present? ? "confirmed" : "pending"
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
  #
  # On ne contrôle que ce qui PREND des places : une création, un créneau ou un
  # nombre de participants qui change, une réservation morte qui revit. Valider
  # ou déclarer la tenue d'une activité déjà posée (souvent au-delà de la
  # capacité, par l'équipe) ne la remet pas en cause — la validation d'une
  # activité de 43 personnes répondait 422 (Michael 2026-10-01, CLAUDY-7Z).
  def participants_fit_in_availability
    return if capacity_override
    return if experience_availability.blank? || participants.to_i <= 0
    return if cancelled? || refused?
    return unless takes_new_spots?

    spots = experience_availability.available_spots(ignoring: id)
    return if spots.nil? || participants.to_i <= spots

    errors.add(:participants,
               spots.zero? ? "— ce créneau est complet" : "— il ne reste que #{spots} place(s) sur ce créneau")
  end

  def takes_new_spots?
    return true if new_record?
    return true if will_save_change_to_experience_availability_id?
    return true if will_save_change_to_participants? && participants.to_i > participants_in_database.to_i

    will_save_change_to_status? && %w[cancelled refused].include?(status_in_database)
  end

  def set_default_status
    self.status ||= "pending"
  end

  # Même règle pour qui est payé et combien : une fois sur un relevé, on ne
  # réécrit ni la personne ni le montant.
  def payout_frozen_once_reported
    return unless persisted? && carrier_statement_line.present?
    return unless will_save_change_to_performed_by_id? || will_save_change_to_carrier_fee_cents?

    errors.add(:base,
               "cette prestation figure sur un relevé de rémunération : qui la reçoit et combien sont figés. " \
               "Passez par une contre-passation du relevé.")
  end

  def outcome_frozen_once_reported
    return unless persisted? && will_save_change_to_outcome?
    return if carrier_statement_line.nil?

    errors.add(:outcome,
               "cette prestation figure sur un relevé de rémunération : son verdict est figé. " \
               "Passez par une contre-passation du relevé.")
  end
end
