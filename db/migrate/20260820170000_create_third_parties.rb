class CreateThirdParties < ActiveRecord::Migration[8.1]
  def change
    create_table :third_parties do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.boolean :active, null: false, default: true
      t.references :customer, foreign_key: true
      t.references :human, foreign_key: true
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :third_parties, :code, unique: true
    add_index :third_parties, :deleted_at

    add_reference :journal_lines, :third_party, foreign_key: true, index: true
  end
end
