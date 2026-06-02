class CreateExperienceAvailabilities < ActiveRecord::Migration[7.0]
  def change
    create_table :experience_availabilities do |t|
      t.references :experience, null: false, foreign_key: true
      t.date :available_on
      t.string :starts_at
      t.integer :duration_minutes
      t.integer :max_participants
      t.string :notes

      t.timestamps
    end
  end
end
