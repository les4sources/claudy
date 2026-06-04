class AddListAndCarrierToAgendaItems < ActiveRecord::Migration[7.0]
  def change
    add_column :agenda_items, :list, :integer, null: false, default: 0
    add_reference :agenda_items, :carrier, foreign_key: { to_table: :humans }, null: true

    add_index :agenda_items, [:gathering_id, :list, :position]
  end
end
