# Les fonds de carte du domaine (epic #348, phase 1).
#
# Un fond de carte est DATÉ : le vol drone de 2023 reste consultable quand
# celui de 2027 arrivera (décision 11). C'est pour ça qu'il y a une table
# plutôt qu'une constante — chaque vol est une ligne, et une seule porte le
# drapeau `default`.
#
# Les tuiles elles-mêmes ne sont PAS en base ni dans le dépôt (décision 13) :
# elles vivent sous `storage/map-tiles/<key>/`, et cette table dit seulement où
# les chercher et jusqu'où zoomer.
class CreateMapBaseLayers < ActiveRecord::Migration[8.1]
  def change
    create_table :map_base_layers do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.date :captured_on
      t.integer :min_zoom
      t.integer :max_zoom
      # `{south, west, north, east}` — l'emprise du vol. Hors de cette emprise
      # il n'y a pas de tuile, et c'est normal : le fond reste uni.
      t.jsonb :bounds, null: false, default: {}
      t.boolean :default, null: false, default: false
      t.boolean :has_relief, null: false, default: false

      t.timestamps
    end

    add_index :map_base_layers, :key, unique: true
  end
end
