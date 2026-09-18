# Une Pizza Party privée réservée et PAYÉE sur Tranches de Vie (l'app de la
# boulangerie), rattachée à la main au séjour de groupe géré ici (issue #339).
#
# Pourquoi elle existe : quand le séjour est facturable, la compta doit faire
# figurer la party sur la facture du séjour. Sans ce rattachement, la personne
# qui tient la compta ne voit nulle part que ce paiement existe.
#
# Le rattachement est un MIROIR en lecture seule de la commande Tranches de Vie :
# on n'écrit jamais là-bas. `payload` garde la dernière réponse brute, pour
# pouvoir expliquer après coup ce qu'on a vu.
class PartyReservation < ApplicationRecord
  SOURCES = %w[tranchesdevie].freeze
  STATUSES = %w[active refunded cancelled].freeze

  STATUS_LABELS = {
    "active" => "Active",
    "refunded" => "Remboursée",
    "cancelled" => "Annulée"
  }.freeze

  belongs_to :stay
  # Le paiement miroir créé au rattachement. Nullable : une party dont le
  # paiement a été supprimé à la main reste lisible.
  belongs_to :payment, optional: true

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :price_cents

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :external_id, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # Unicité sur les lignes VIVANTES seulement, comme l'index partiel en base.
  # `validates :uniqueness` ne convient pas : il construit sa requête en
  # `unscoped` et verrait donc les parties détachées, interdisant de rattacher à
  # nouveau une party qu'on avait retirée par erreur.
  validate :external_id_unique_among_live

  scope :active, -> { where(status: "active") }
  scope :settled_elsewhere, -> { where.not(status: "active") }
  scope :ordered, -> { order(Arel.sql("held_on NULLS LAST"), :id) }

  def active? = status == "active"
  def refunded? = status == "refunded"
  def cancelled? = status == "cancelled"

  def status_label = STATUS_LABELS.fetch(status, status)


  # Ce qui s'affiche sur une ligne : « 9 octobre · soir · Scouts de Namur · 18 pers. »
  def summary
    parts = []
    parts << I18n.l(held_on, format: :short) if held_on.present?
    parts << slot if slot.present?
    parts << group_name if group_name.present?
    parts << "#{persons} pers." if persons.to_i.positive?
    parts.join(" · ")
  end

  private

  def external_id_unique_among_live
    return if external_id.blank?

    scope = self.class.where(source: source, external_id: external_id)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:external_id, "cette party est déjà rattachée à un séjour")
  end
end
