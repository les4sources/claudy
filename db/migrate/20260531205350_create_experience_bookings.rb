class CreateExperienceBookings < ActiveRecord::Migration[7.0]
  def change
    create_table :experience_bookings do |t|
      t.references :experience_availability, null: false, foreign_key: true
      t.references :stay, null: false, foreign_key: true
      t.integer :participants
      t.string :status
      t.text :notes

      t.timestamps
    end
  end
end
