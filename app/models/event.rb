# == Schema Information
#
# Table name: events
#
#  id                      :bigint           not null, primary key
#  attendees               :integer
#  deleted_at              :datetime
#  ends_at                 :datetime
#  name                    :string
#  notes                   :text
#  organizer_share_percent :integer
#  sales_amount_cents      :integer
#  starts_at               :datetime
#  status                  :string
#  url                     :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  event_category_id       :bigint           not null
#  team_id                 :bigint
#
# Indexes
#
#  index_events_on_event_category_id  (event_category_id)
#  index_events_on_team_id            (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_category_id => event_categories.id)
#  fk_rails_...  (team_id => teams.id)
#
class Event < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }

  belongs_to :event_category
  # Le pôle qui porte l'événement (epic #245, décision 2).
  belongs_to :team, optional: true

  has_many :event_organizers, dependent: :destroy
  has_many :organizers, through: :event_organizers, source: :human
  has_many :event_costs, dependent: :destroy
  # Les réservations d'espace rattachées : elles se proposent en frais fixes
  # avec leur prix persisté, sans jamais le recalculer.
  has_many :space_bookings, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :sales_amount_cents, allow_nil: true

  has_rich_text :notes

  validates :name,
            presence: true
  validates :organizer_share_percent,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :starts_at_date,
            presence: { message: "Veuillez spécifier une date de début" }
  validates :ends_at_date,
            presence: { message: "Veuillez spécifier une date de fin" }

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time

  by_star_field :starts_at, :ends_at

  # --- Partage avec les organisateurs (epic #245, phase 1) ---

  # Le taux qui revient aux organisateurs. Celui de l'événement s'il est posé,
  # sinon la clé `event.organizer_share` de Paramètres > Tarifs (70 %).
  def effective_organizer_share_percent
    return organizer_share_percent if organizer_share_percent.present?

    Pricing::Catalog.event_organizer_share_percent
  end

  def organizer_share_overridden? = organizer_share_percent.present?

  # Les frais fixes déduits avant le partage.
  def fixed_costs_cents = event_costs.sum(:amount_cents)

  def organizer_weights_total = event_organizers.sum(:weight)

  # Sans organisateur, ou avec des poids qui totalisent zéro, il n'y a rien à
  # répartir. L'écran le dit — sans bloquer la saisie, parce qu'on encode
  # souvent l'événement avant de savoir qui le portera.
  def shareable? = event_organizers.any? && organizer_weights_total.positive?

  # Les réservations d'espace rattachées qui n'ont pas encore été passées en
  # frais — celles qu'on peut encore ajouter en un clic.
  def space_bookings_not_yet_costed
    costed = event_costs.where(source_type: "SpaceBooking").pluck(:source_id)
    space_bookings.where.not(id: costed)
  end
end
