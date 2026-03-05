class CreateCycleActions < ActiveRecord::Migration[7.0]
  def change
    create_table :cycle_actions do |t|
      t.string :label, null: false
      t.decimal :hours, precision: 5, scale: 2
      t.integer :category, null: false, default: 0
      t.boolean :completed, default: false
      t.references :human, null: false, foreign_key: true
      t.bigint :delegate_to_human_id
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cycle_actions, :delegate_to_human_id
    add_index :cycle_actions, :category
    add_index :cycle_actions, :completed
    add_foreign_key :cycle_actions, :humans, column: :delegate_to_human_id
  end
end
