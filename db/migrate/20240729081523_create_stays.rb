class CreateStays < ActiveRecord::Migration[7.0]
  def change
    create_table :stays do |t|
      t.references :user, null: false, foreign_key: true
      t.date :start_date
      t.date :end_date
      t.string :status
      t.timestamps
    end
  end
end