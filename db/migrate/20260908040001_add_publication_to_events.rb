class AddPublicationToEvents < ActiveRecord::Migration[8.1]
  # Publication d'un événement sur le site les4sources.be : `published_at` nul
  # = brouillon ; `slug` figé à la première publication (URL publique
  # `/evenements/<slug>`) ; `summary`, `location` et `price_text` sont les
  # champs publics courts. La description publique est un ActionText
  # (`public_description`, distinct des `notes` internes) et l'image un
  # ActiveStorage (`image`) — ni l'un ni l'autre n'a de colonne ici.
  def change
    add_column :events, :published_at, :datetime
    add_column :events, :slug, :string
    add_column :events, :summary, :string
    add_column :events, :location, :string
    add_column :events, :price_text, :string
    add_index :events, :slug, unique: true
  end
end
