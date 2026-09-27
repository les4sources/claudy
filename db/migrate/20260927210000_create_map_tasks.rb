# Carte du domaine (epic #348, phase 6) : la consigne de gestion devient un plan
# de travail mois par mois. Une tâche porte sur un objet de la carte — et, à la
# phase 7, sur une plante : d'où le porteur polymorphe (`subject`), dont le type
# reste une liste fermée côté modèle (`MapTask::SUBJECT_TYPES`).
#
# Les mois sont un tableau d'entiers (1 à 12) plutôt qu'une table de jointure :
# une tâche revient au plus douze fois par an, et « les tâches de mars » est un
# simple `months @> '{3}'`, servi par l'index GIN.
class CreateMapTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :map_tasks do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :label, null: false
      # Pas de défaut en base : il dépend du porteur (terrain pour un objet de la
      # carte, nourricier pour une plante), c'est le modèle qui le pose.
      t.string :sector, null: false
      t.integer :months, array: true, null: false, default: []
      t.string :frequency
      t.text :notes
      t.integer :position
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_tasks, %i[subject_type subject_id]
    add_index :map_tasks, :months, using: :gin
    add_index :map_tasks, :deleted_at
  end
end
