# Une journée de coworking posée sur un pack (epic #126, Phase 1).
#
# Trois bureaux au total : la capacité est GLOBALE (3 réservations vivantes par
# jour, toutes clientes confondues), pas par ressource nommée — on ne réserve
# pas « le bureau 2 ».
#
# Le domaine est indépendant du canal `SpaceBooking` de l'espace « Coworking »
# historique : aucun `SpaceReservation` n'est créé ni consulté ici.
class CoworkingReservation < ApplicationRecord
  DAILY_CAPACITY = 3

  belongs_to :coworking_pack
  belongs_to :customer

  has_paper_trail
  has_soft_deletion default_scope: true

  validates :date, presence: true
  validate :date_is_a_weekday
  validate :pack_not_expired
  validate :pack_has_credits, on: :create
  validate :daily_capacity_available
  validate :not_already_booked_by_pack

  before_validation :denormalize_customer

  scope :ordered, -> { order(date: :asc) }
  scope :on, ->(date) { where(date: date) }
  scope :between, ->(from, to) { where(date: from..to) }

  # Occupation d'un jour donné, tous packs confondus.
  def self.count_on(date) = on(date).count

  def self.remaining_on(date) = [DAILY_CAPACITY - count_on(date), 0].max

  private

  def denormalize_customer
    self.customer ||= coworking_pack&.customer
  end

  def date_is_a_weekday
    return if date.blank?
    return if (1..5).cover?(date.wday)

    errors.add(:date, "doit être un jour de semaine (lundi à vendredi)")
  end

  def pack_not_expired
    return if date.blank? || coworking_pack.nil?
    return unless coworking_pack.expired?(date)

    errors.add(:coworking_pack, "est expiré à cette date")
  end

  def pack_has_credits
    return if coworking_pack.nil?
    return if coworking_pack.credits_left?

    errors.add(:coworking_pack, "n'a plus de journée disponible")
  end

  def daily_capacity_available
    return if date.blank?

    taken = self.class.on(date).where.not(id: id).count
    return if taken < DAILY_CAPACITY

    errors.add(:date, "est complet (#{DAILY_CAPACITY} bureaux déjà réservés)")
  end

  def not_already_booked_by_pack
    return if date.blank? || coworking_pack_id.blank?

    duplicate = self.class.on(date)
                    .where(coworking_pack_id: coworking_pack_id)
                    .where.not(id: id)
                    .exists?
    return unless duplicate

    errors.add(:date, "est déjà réservé pour ce pack")
  end
end
