# Les fiches des plantes bio-indicatrices : une par espèce, remplie à sa
# première rencontre sur le terrain et reprise ensuite par chaque relevé.
class CreateBioindicatorSpecies < ActiveRecord::Migration[8.1]
  def change
    create_table :bioindicator_species do |t|
      t.string :latin_name, null: false
      t.string :name, null: false
      t.string :family
      t.text :common_names
      t.text :description
      t.text :biotope_primary
      t.text :biotope_secondary
      t.text :indicator_traits
      t.string :agronomy
      t.string :ecology
      t.jsonb :indicators, null: false, default: []
      t.text :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :bioindicator_species, "lower(latin_name)", unique: true, where: "deleted_at IS NULL",
                                                          name: "index_bioindicator_species_on_lower_latin_name_alive"
    add_index :bioindicator_species, :deleted_at
  end
end
