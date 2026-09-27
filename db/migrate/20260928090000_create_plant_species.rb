# Carte du domaine (epic #348, phase 7) : le catalogue LOCAL des espèces
# nourricières (décision de Michael du 2026-09-27 : pas de lien Terranova).
# Une espèce porte les fenêtres de récolte par défaut que ses plantes héritent,
# et de quoi tenir une vraie fiche botanique (champs repris de la base Notion).
class CreatePlantSpecies < ActiveRecord::Migration[8.1]
  def change
    create_table :plant_species do |t|
      t.string :name, null: false
      t.string :latin_name
      t.string :family
      t.text :common_names
      t.string :hardiness
      t.string :height
      t.string :spread
      t.string :exposure, array: true, null: false, default: []
      t.string :edible_parts, array: true, null: false, default: []
      t.string :wikipedia_url
      t.text :notes
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    # « Pommier » et « pommier » sont la même espèce ; une espèce supprimée
    # libère son nom.
    add_index :plant_species, "lower(name)", unique: true, where: "deleted_at IS NULL",
                                             name: "index_plant_species_on_lower_name_alive"
    add_index :plant_species, :deleted_at
  end
end
