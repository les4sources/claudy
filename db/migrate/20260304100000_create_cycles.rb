class CreateCycles < ActiveRecord::Migration[7.0]
  def change
    create_table :cycles do |t|
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :cycles, [:start_date, :end_date]
  end
end
