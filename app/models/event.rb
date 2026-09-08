# == Schema Information
#
# Table name: events
#
#  id                 :bigint           not null, primary key
#  attendees          :integer
#  deleted_at         :datetime
#  ends_at            :datetime
#  location           :string
#  name               :string
#  notes              :text
#  price_text         :string
#  published_at       :datetime
#  sales_amount_cents :integer
#  slug               :string
#  starts_at          :datetime
#  status             :string
#  summary            :string
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_category_id  :bigint           not null
#
# Indexes
#
#  index_events_on_event_category_id  (event_category_id)
#  index_events_on_slug               (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (event_category_id => event_categories.id)
#
class Event < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }

  # Publication sur le site les4sources.be : `published_at`, `slug`, rebuild.
  include Publishable

  SUMMARY_MAX_LENGTH = 200

  belongs_to :event_category

  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :sales_amount_cents, allow_nil: true

  has_rich_text :notes
  # Contenu PUBLIC (fiche sur le site), distinct des notes internes.
  has_rich_text :public_description
  has_one_attached :image

  validates :name,
            presence: true
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

  by_star_field :starts_at, :ends_at

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
