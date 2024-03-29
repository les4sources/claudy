class AddUuidToPayments < ActiveRecord::Migration[7.0]
  def change
    add_column :payments, :uuid, :uuid, default: "gen_random_uuid()", null: false
    add_index :payments, :uuid, unique: true
  end
end
