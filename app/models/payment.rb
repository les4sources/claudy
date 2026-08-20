# == Schema Information
#
# Table name: payments
#
#  id                         :uuid             not null, primary key
#  amount_cents               :integer          default(0), not null
#  deleted_at                 :datetime
#  paid_on                    :date
#  payment_method             :string
#  status                     :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  booking_id                 :bigint
#  coworking_pack_id          :bigint
#  space_booking_id           :bigint
#  stay_id                    :bigint
#  stripe_checkout_session_id :string
#  stripe_payment_intent_id   :string
#
# Indexes
#
#  index_payments_on_booking_id         (booking_id)
#  index_payments_on_coworking_pack_id  (coworking_pack_id)
#  index_payments_on_id                 (id) UNIQUE
#  index_payments_on_space_booking_id   (space_booking_id)
#  index_payments_on_stay_id            (stay_id)
#
# Foreign Keys
#
#  fk_rails_...  (booking_id => bookings.id)
#  fk_rails_...  (coworking_pack_id => coworking_packs.id)
#  fk_rails_...  (space_booking_id => space_bookings.id)
#  fk_rails_...  (stay_id => stays.id)
#
class Payment < ApplicationRecord
  # notify ActiveRecord that the default sort order should be created_at
  self.implicit_order_column = :created_at

  # Stay-first (issue #26, Phase 2 puis Phase 4) : le séjour est devenu l'ANCRE
  # du paiement. Le booking n'est plus obligatoire — un séjour sans hébergement
  # (camping, espaces) n'en a pas. Il reste renseigné pour tout le canal
  # historique, et la colonne `booking_id` ne sera retirée que bien plus tard.
  belongs_to :booking, optional: true
  # Phase 4 (« verrouillage ») : le stay devient OBLIGATOIRE. On retire
  # `optional: true` pour réactiver la validation de présence par défaut de
  # `belongs_to` — un Payment sans stay_id est désormais invalide. Les données
  # legacy déjà persistées sans stay ne sont pas re-validées (pas de re-save),
  # et sont rattrapées par `rake payments:backfill_stay_from_booking`.
  #
  # Coworking (epic #126, Phase 1) : un paiement peut désormais s'ancrer sur un
  # `CoworkingPack` au lieu d'un séjour — le coworking n'est PAS un séjour.
  # L'invariant du verrouillage Phase 4 devient donc « stay_id OU
  # coworking_pack_id » : un paiement sans ancre reste invalide.
  belongs_to :stay, optional: true
  belongs_to :coworking_pack, optional: true

  # Provenance de facturation des espaces (facturation espaces → paiements).
  # Optionnel : seuls les Payment issus de la rake `space_bookings:billing_to_payments`
  # le portent. Sert de trace d'audit ET de clé d'idempotence de cette rake
  # (un seul Payment `paid` + un seul Payment `pending` par SpaceBooking).
  belongs_to :space_booking, optional: true

  monetize :amount_cents, allow_nil: false

  # Table de versions dédiée : la PK de Payment est un UUID, incompatible avec
  # `versions.item_id bigint` (issue #52). Voir `PaymentVersion`.
  has_paper_trail versions: { class_name: "PaymentVersion" }
  has_soft_deletion default_scope: true

  validates :amount, numericality: { greater_than: 0.0 }
  validates :payment_method, presence: true
  validate :anchored_on_stay_or_coworking_pack

  scope :paid, -> { where(status: "paid") }
  scope :pending, -> { where(status: "pending") }

  # Statuts de séjour qui valent « annulé ». Les deux orthographes coexistent
  # dans l'historique (`canceled` posé par l'app, `cancelled` par des imports).
  CANCELED_STAY_STATUSES = %w[canceled cancelled].freeze

  # Ce qui mérite d'apparaître dans le journal des paiements (Michael
  # 2026-08-20). Le journal sert à retrouver de l'ARGENT, pas des intentions :
  #   * un séjour « en attente » n'a encore rien encaissé de ferme — même un
  #     paiement marqué payé y reste une écriture provisoire, on masque tout ;
  #   * un séjour annulé ne garde que ce qui a réellement été encaissé (c'est
  #     ce qu'il faudra rembourser ou retenir) ; ses paiements en attente n'ont
  #     plus d'objet.
  # Un paiement SANS séjour (coworking, canal booking historique) n'est jamais
  # masqué : la règle ne parle que des séjours.
  scope :journalable, lambda {
    left_joins(:stay)
      .where(<<~SQL.squish, canceled: CANCELED_STAY_STATUSES)
        stays.id IS NULL
        OR (COALESCE(stays.status, '') <> 'pending'
            AND (COALESCE(stays.status, '') NOT IN (:canceled)
                 OR payments.status = 'paid'))
      SQL
  }

  def paid?
    self.status == "paid"
  end

  def pending?
    self.status == "pending"
  end

  # Date qui fait FOI pour l'affichage et le rapprochement bancaire : la date
  # d'encaissement saisie si elle l'a été, la date de saisie sinon. Tout
  # l'historique n'a que `created_at` — d'où le repli, qui évite un backfill.
  def effective_date
    paid_on || created_at.to_date
  end

  private

  # Un paiement doit toujours savoir CE QU'IL PAIE : un séjour, ou un pack de
  # coworking. Jamais rien, jamais les deux.
  def anchored_on_stay_or_coworking_pack
    return if stay_id.present? ^ coworking_pack_id.present?

    if stay_id.present?
      errors.add(:base, "Un paiement ne peut pas porter à la fois un séjour et un pack de coworking")
    else
      errors.add(:stay, "doit être renseigné (ou un pack de coworking)")
    end
  end
end
