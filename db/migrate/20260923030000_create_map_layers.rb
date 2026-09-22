# Les couches typées de la carte (epic #348, phase 2, décision 1) : tout ce qui
# se dessine sur la carte vit dans une couche qu'on allume ou éteint. Une couche
# par type pour la plupart ; plusieurs pour les réseaux et les dessins.
class CreateMapLayers < ActiveRecord::Migration[8.1]
  def change
    create_table :map_layers do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_layers, :kind
    add_index :map_layers, :deleted_at
  end
end
