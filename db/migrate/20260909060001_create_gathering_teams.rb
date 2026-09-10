# Epic #239, phase 2 — un rassemblement concerne des pôles.
#
# Table de jointure nue : le rattachement n'a pas d'attributs propres, et lui en
# inventer (un rôle, un ordre) serait décider à la place du collectif. Aucun pôle
# rattaché veut dire « transversal » — c'est l'absence qui porte le sens, pas un
# drapeau de plus.
class CreateGatheringTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :gathering_teams do |t|
      t.references :gathering, null: false, foreign_key: true
      t.references :team,      null: false, foreign_key: true

      t.timestamps
    end

    add_index :gathering_teams, %i[gathering_id team_id], unique: true
  end
end
