class CreateServices < ActiveRecord::Migration[7.0]
  def change
    create_table :services do |t|
      t.string :name
      t.references :human, null: true, foreign_key: true
      t.string :summary
      t.text :description
      t.string :photo
      t.timestamp :deleted_at

      t.timestamps
    end

    add_monetize :services, :price, amount: { null: true, default: nil }, currency: { present: false }
  end
end
