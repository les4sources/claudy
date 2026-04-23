class CreateAgendaItems < ActiveRecord::Migration[7.0]
  def change
    create_table :agenda_items do |t|
      t.references :gathering, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :humans }
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.boolean :completed, null: false, default: false

      t.timestamps
    end
    add_column :agenda_items, :deleted_at, :datetime
    add_index :agenda_items, [:gathering_id, :position]
  end
end
