class CreateHumans < ActiveRecord::Migration[7.0]
  def change
    create_table :humans do |t|
      t.string :name
      t.string :email
      t.string :photo
      t.string :summary
      t.text :description
      t.timestamp :deleted_at

      t.timestamps
    end
  end
end
