class CreateTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :teams do |t|
      t.string :name
      t.text :description
      t.timestamp :deleted_at

      t.timestamps
    end
  end
end
