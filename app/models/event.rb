# == Schema Information
#
# Table name: events
#
#  id                      :bigint           not null, primary key
#  attendees               :integer
#  deleted_at              :datetime
#  ends_at                 :datetime
#  location                :string
#  name                    :string
#  notes                   :text
#  organizer_share_percent :integer
#  price_text              :string
#  published_at            :datetime
#  sales_amount_cents      :integer
#  slug                    :string
#  starts_at               :datetime
#  status                  :string
#  summary                 :string
#  url                     :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  event_category_id       :bigint           not null
#  team_id                 :bigint
#
# Indexes
#
#  index_events_on_event_category_id  (event_category_id)
#  index_events_on_slug               (slug) UNIQUE
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

  # Publication sur le site les4sources.be : `published_at`, `slug`, rebuild.
  include Publishable

  SUMMARY_MAX_LENGTH = 200

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

  # Les allocations de trésorerie qui pointent CET événement (epic #245,
  # phase 2). C'est par elles que les recettes réelles arrivent — le montant
  # saisi à la main (`sales_amount_cents`) n'était qu'une estimation en
  # attendant.
  has_many :cash_allocations, as: :document, dependent: :nullify

  monetize :sales_amount_cents, allow_nil: true

  has_rich_text :notes
  # Contenu PUBLIC (fiche sur le site), distinct des notes internes.
  has_rich_text :public_description
  has_one_attached :image

  validates :name,
            presence: true
  validates :organizer_share_percent,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :starts_at_date,
            presence: { message: "Veuillez spécifier une date de début" }
  validates :ends_at_date,
            presence: { message: "Veuillez spécifier une date de fin" }
  validates :summary,
            length: { maximum: SUMMARY_MAX_LENGTH }
  validate :image_must_be_an_image

  attr_accessor :starts_at_date, :starts_at_time, :ends_at_date, :ends_at_time
  # Événement source d'une duplication (voir `Events::DuplicateService`) :
  # l'image est reprise à la création.
  attr_accessor :duplicate_of_id

  before_validation :rehydrate_form_dates

  # --- Recettes réelles (epic #245, phase 2) ---

  # Ce qui a été encaissé et rattaché. Un remboursement est une allocation
  # négative : la somme est donc le NET, pas le brut.
  def recorded_revenue_cents = cash_allocations.sum(:amount_cents)

  def recorded_revenue? = cash_allocations.exists?

  # Les séjours qui touchent l'événement par une réservation d'espace, SANS que
  # leur argent lui soit rattaché. On les signale, on ne rattache rien d'office :
  # un séjour peut très bien avoir loué la salle pour autre chose le même jour.
  def linked_stays
    stay_ids = space_bookings.includes(stay_item: :stay).filter_map { |booking| booking.stay&.id }.uniq
    Stay.where(id: stay_ids)
  end

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

  # « Toute la journée » = aucune heure saisie : le formulaire pose alors les
  # deux bornes à minuit.
  def all_day?
    return false if starts_at.blank? || ends_at.blank?

    starts_at == starts_at.beginning_of_day && ends_at == ends_at.beginning_of_day
  end

  # Base du slug public : titre + mois/année en français, sans doubler un mois
  # ou une année déjà présents dans le titre (« pizza-party-septembre-2026 »).
  def slug_base
    title = name.to_s.parameterize
    return title if starts_at.blank?

    parts = title.split("-")
    month = I18n.l(starts_at.to_date, format: "%B", locale: :fr).parameterize
    year = starts_at.year.to_s
    [title, (month unless parts.include?(month)), (year unless parts.include?(year))].compact.join("-")
  end

  def public_path_prefix
    "/evenements"
  end

  private

  # Les validations de dates portent sur les champs VIRTUELS du formulaire.
  # Pour qu'une sauvegarde programmatique (publication, duplication de
  # l'image…) reste valide, on les remplit depuis les colonnes quand le
  # formulaire ne les a pas fournis.
  def rehydrate_form_dates
    self.starts_at_date = starts_at.to_date if starts_at_date.nil? && starts_at.present?
    self.ends_at_date = ends_at.to_date if ends_at_date.nil? && ends_at.present?
  end

  def image_must_be_an_image
    return unless image.attached?
    return if image.blob.content_type.to_s.start_with?("image/")

    errors.add(:image, "doit être une image (JPG, PNG, WebP…)")
  end
end
