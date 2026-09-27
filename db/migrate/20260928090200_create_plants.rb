# Carte du domaine (epic #348, phase 7) : chaque plante nourricière du domaine
# et son dossier. Une plante placée pointe vers un `MapFeature` point de la
# couche Plantes ; sans lui (`map_feature_id` nul), elle est « à placer » —
# c'est le cas de toutes les plantes importées de Notion (phase 8).
#
# Les listes fermées (statut, santé, production, port, strate, population,
# conditionnement) sont des chaînes validées côté modèle (`Plant::STATUSES`…),
# comme ailleurs dans la carte.
class CreatePlants < ActiveRecord::Migration[8.1]
  def change
    create_table :plants do |t|
      t.references :map_feature, foreign_key: true, index: false
      # L'`ID` de la base Notion : unique quand il existe.
      t.integer :number
      t.string :name, null: false
      t.references :plant_species, foreign_key: true
      t.references :plant_variety, foreign_key: true
      t.string :zone
      t.string :status, null: false, default: "to_place"
      t.string :health
      t.string :production
      t.string :habit
      t.string :stratum
      t.string :population
      t.integer :plant_count
      t.string :stock_type
      t.string :nursery
      t.integer :purchase_price_cents
      t.date :planted_on
      t.integer :planted_year
      t.integer :altitude
      t.text :notes
      t.string :notion_url
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :plants, :number, unique: true, where: "number IS NOT NULL AND deleted_at IS NULL",
                                name: "index_plants_on_number_alive"
    # Un point de la carte ne représente qu'une plante vivante.
    add_index :plants, :map_feature_id, unique: true, where: "map_feature_id IS NOT NULL AND deleted_at IS NULL",
                                        name: "index_plants_on_map_feature_id_alive"
    add_index :plants, :status
    add_index :plants, :zone
    add_index :plants, :deleted_at
  end
end
