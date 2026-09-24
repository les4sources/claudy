# Notes prises en réunion sur un point de l'ODJ. Une note appartient au couple
# (point, rassemblement) : quand un point est reporté, ses notes restent sur le
# rassemblement où elles ont été prises, et le suivant repart d'une page blanche.
class CreateAgendaItemNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :agenda_item_notes do |t|
      t.references :agenda_item, null: false, foreign_key: true
      t.references :gathering, null: false, foreign_key: true
      t.timestamps
    end
    add_index :agenda_item_notes, [:agenda_item_id, :gathering_id], unique: true
  end
end
