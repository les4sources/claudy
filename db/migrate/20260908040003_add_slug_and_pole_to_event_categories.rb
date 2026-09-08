class AddSlugAndPoleToEventCategories < ActiveRecord::Migration[8.1]
  # Les catégories d'événements deviennent publiques (site les4sources.be) :
  # un `slug` stable, un `pole` de la charte (facultatif, choisi par l'éditrice
  # — aucune correspondance n'est inventée ici) et une couleur en hexadécimal.
  # Les couleurs étaient des noms Tailwind (« teal », « amber »…) composés en
  # classes à l'exécution ; on les convertit vers le hex de la nuance 600, la
  # valeur inconnue prend le teal de la charte.
  TAILWIND_TO_HEX = {
    "slate" => "#475569", "gray" => "#4b5563", "zinc" => "#52525b", "neutral" => "#525252",
    "stone" => "#57534e", "red" => "#dc2626", "orange" => "#ea580c", "amber" => "#d97706",
    "yellow" => "#ca8a04", "lime" => "#65a30d", "green" => "#16a34a", "emerald" => "#059669",
    "teal" => "#0d9488", "cyan" => "#0891b2", "sky" => "#0284c7", "blue" => "#2563eb",
    "indigo" => "#4f46e5", "violet" => "#7c3aed", "purple" => "#9333ea", "fuchsia" => "#c026d3",
    "pink" => "#db2777", "rose" => "#e11d48"
  }.freeze
  DEFAULT_HEX = "#224246".freeze

  class MigrationEventCategory < ActiveRecord::Base
    self.table_name = "event_categories"
  end

  def up
    add_column :event_categories, :slug, :string
    add_column :event_categories, :pole, :string
    add_index :event_categories, :slug, unique: true

    MigrationEventCategory.reset_column_information
    taken = {}
    MigrationEventCategory.order(:id).find_each do |category|
      base = category.name.to_s.parameterize.presence || "categorie-#{category.id}"
      slug = base
      counter = 1
      while taken[slug]
        counter += 1
        slug = "#{base}-#{counter}"
      end
      taken[slug] = true

      color = category.color.to_s.strip.downcase
      hex = color.match?(/\A#[0-9a-f]{6}\z/) ? color : TAILWIND_TO_HEX.fetch(color, DEFAULT_HEX)
      category.update_columns(slug: slug, color: hex)
    end
  end

  def down
    MigrationEventCategory.reset_column_information
    MigrationEventCategory.find_each do |category|
      name = TAILWIND_TO_HEX.key(category.color.to_s.downcase)
      category.update_columns(color: name) if name
    end

    remove_index :event_categories, :slug
    remove_column :event_categories, :pole
    remove_column :event_categories, :slug
  end
end
