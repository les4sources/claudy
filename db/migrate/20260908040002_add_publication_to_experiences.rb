class AddPublicationToExperiences < ActiveRecord::Migration[8.1]
  # Publication d'une activité sur le site (catalogue) : `published_at` nul =
  # brouillon ; `slug` figé à la première publication (`/catalogue/<slug>`).
  def change
    add_column :experiences, :published_at, :datetime
    add_column :experiences, :slug, :string
    add_index :experiences, :slug, unique: true
  end
end
