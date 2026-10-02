# Carte du domaine (epic #348, phase 7) : les variétés d'une espèce
# (« Reinette Hernaut » sous « Pommier »). Soft-delete et PaperTrail comme le
# reste du catalogue.
class CreatePlantVarieties < ActiveRecord::Migration[8.1]
  def change
    create_table :plant_varieties do |t|
      t.references :plant_species, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.text :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :plant_varieties, "plant_species_id, lower(name)", unique: true, where: "deleted_at IS NULL",
                                                                 name: "index_plant_varieties_on_species_and_lower_name_alive"
    add_index :plant_varieties, :deleted_at
  end
end
