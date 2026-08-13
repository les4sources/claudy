# Membres d'un ménage (issue #155).
#
# `human_id` est NULLABLE à dessein : un enfant, un conjoint ou un colocataire
# n'est pas forcément un membre de l'équipe. `name` porte donc toujours le nom
# affichable, même sans `Human` derrière.
#
# `started_on` / `ended_on` bornent la présence dans le ménage. C'est ce qui
# permet de recompter les adultes d'un mois passé sans mentir : une naissance
# ou un départ survenu depuis ne doit pas réécrire un décompte de 2024.
class CreateHouseholdMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :household_members do |t|
      t.references :household, null: false, foreign_key: true
      t.references :human, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "adult"
      t.date :born_on
      t.date :started_on, null: false
      t.date :ended_on
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :household_members, [:household_id, :started_on]
    add_index :household_members, :deleted_at
  end
end
