# Carte du domaine (epic #348, phase 7) : quand récolter quoi. Une fenêtre
# appartient à une espèce (valeur par défaut) ou à une plante (surcharge) ; une
# plante qui a au moins une fenêtre propre n'hérite plus de celles de son
# espèce (`Plant#harvest_windows_effective`).
#
# Les mois sont un tableau d'entiers servi par un index GIN, comme les tâches
# (phase 6) : « ce qui se récolte en juillet » est un `months @> '{7}'`.
class CreatePlantHarvestWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :plant_harvest_windows do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :part, null: false
      t.integer :months, array: true, null: false, default: []
      t.timestamps
    end
    add_index :plant_harvest_windows, %i[owner_type owner_id part], unique: true
    add_index :plant_harvest_windows, :months, using: :gin
  end
end
