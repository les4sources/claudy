class CreateUnavailabilities < ActiveRecord::Migration[7.0]
  def change
    create_table :unavailabilities do |t|
      t.date :date
      t.references :lodging, null: false, foreign_key: true

      t.timestamps
    end
  end
end
