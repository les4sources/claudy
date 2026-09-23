# Les objets de la carte (epic #348, phase 2) : le modèle commun de tout ce qui
# se dessine — zones, accès, points, et demain plantes, nœuds de réseau,
# commentaires. Les géométries sont du GeoJSON en jsonb (décision 12 : pas de
# PostGIS) ; surfaces et distances se calculent côté client.
class CreateMapFeatures < ActiveRecord::Migration[8.1]
  def change
    create_table :map_features do |t|
      t.references :map_layer, null: false, foreign_key: true
      t.jsonb :geometry, null: false
      t.string :feature_kind, null: false
      t.jsonb :name_i18n, null: false, default: {}
      t.jsonb :description_i18n, null: false, default: {}
      t.jsonb :properties, null: false, default: {}
      t.references :linked, polymorphic: true, null: true
      t.integer :position, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_features, :feature_kind
    add_index :map_features, :deleted_at
  end
end
