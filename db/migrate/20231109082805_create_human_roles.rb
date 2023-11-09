class CreateHumanRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :human_roles do |t|
      t.references :human, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.date :date

      t.timestamps
    end
  end
end
