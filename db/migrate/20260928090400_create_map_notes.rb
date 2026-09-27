# Carte du domaine (epic #348, phase 7) : les notes datées d'une plante — et
# de tout objet de la carte. « 12 mars : bourgeons gelés. » Le porteur est
# polymorphe, sa liste de types est FERMÉE côté modèle (`MapNote::SUBJECT_TYPES`).
class CreateMapNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :map_notes do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.text :body, null: false
      t.date :noted_on, null: false, default: -> { "CURRENT_DATE" }
      t.references :author, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :map_notes, %i[subject_type subject_id noted_on]
    add_index :map_notes, :deleted_at
  end
end
