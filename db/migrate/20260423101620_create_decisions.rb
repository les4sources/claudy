class CreateDecisions < ActiveRecord::Migration[7.0]
  def change
    create_table :decisions do |t|
      t.string :title, null: false
      t.string :summary, null: false
      t.date :taken_at, null: false
      t.references :recorded_by, null: false, foreign_key: { to_table: :humans }
      t.references :gathering, null: true, foreign_key: { on_delete: :nullify }
      t.references :agenda_item, null: true, foreign_key: { on_delete: :nullify }

      t.timestamps
    end
    add_column :decisions, :deleted_at, :datetime
    add_index :decisions, :taken_at, order: { taken_at: :desc }
  end
end
