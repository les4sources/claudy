# == Schema Information
#
# Table name: event_categories
#
#  id         :bigint           not null, primary key
#  color      :string
#  deleted_at :datetime
#  name       :string
#  pole       :string
#  slug       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_event_categories_on_slug  (slug) UNIQUE
#
class EventCategory < ApplicationRecord
  # Les sept pôles de la charte graphique du site : ils donnent la couleur et
  # le pictogramme des cartes d'événements. Facultatif tant que l'éditrice n'a
  # pas choisi.
  POLES = %w[hebergement convivialite nature artisanat ressourcement vie-collective production].freeze
  POLE_LABELS = {
    "hebergement" => "Hébergement",
    "convivialite" => "Convivialité",
    "nature" => "Nature",
    "artisanat" => "Artisanat",
    "ressourcement" => "Ressourcement",
    "vie-collective" => "Vie collective",
    "production" => "Production"
  }.freeze
  # Teal de la charte.
  DEFAULT_COLOR = "#224246".freeze
  HEX_COLOR = /\A#[0-9a-f]{6}\z/
  # Les couleurs étaient des noms Tailwind (« teal », « amber »…) : on les
  # accepte encore et on les traduit vers le hex de la nuance 600.
  COLOR_NAMES = {
    "slate" => "#475569", "gray" => "#4b5563", "zinc" => "#52525b", "neutral" => "#525252",
    "stone" => "#57534e", "red" => "#dc2626", "orange" => "#ea580c", "amber" => "#d97706",
    "yellow" => "#ca8a04", "lime" => "#65a30d", "green" => "#16a34a", "emerald" => "#059669",
    "teal" => "#0d9488", "cyan" => "#0891b2", "sky" => "#0284c7", "blue" => "#2563eb",
    "indigo" => "#4f46e5", "violet" => "#7c3aed", "purple" => "#9333ea", "fuchsia" => "#c026d3",
    "pink" => "#db2777", "rose" => "#e11d48"
  }.freeze

  has_many :events, dependent: :nullify

  has_paper_trail
  has_soft_deletion default_scope: true

  before_validation :assign_slug
  before_validation :normalize_color

  validates :name, presence: true
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: Publishable::SLUG_FORMAT, message: "ne peut contenir que des minuscules, des chiffres et des tirets" }
  validates :pole,
            inclusion: { in: POLES, message: "n'est pas un pôle de la charte" },
            allow_blank: true
  validates :color,
            format: { with: HEX_COLOR, message: "doit être une couleur hexadécimale (#rrggbb)" }

  def pole_label
    POLE_LABELS[pole]
  end

  private

  # Slug stable dérivé du nom, dédoublonné sur toutes les lignes (corbeille
  # comprise) ; ne change plus une fois posé — le site s'en sert comme clé.
  def assign_slug
    return if slug.present? || name.blank?

    base = name.parameterize.presence || "categorie"
    scope = EventCategory.unscoped
    scope = scope.where.not(id: id) if persisted?
    candidate = base
    counter = 1
    while scope.exists?(slug: candidate)
      counter += 1
      candidate = "#{base}-#{counter}"
    end
    self.slug = candidate
  end

  def normalize_color
    value = color.to_s.strip.downcase
    self.color = COLOR_NAMES.fetch(value, value).presence || DEFAULT_COLOR
  end
end
