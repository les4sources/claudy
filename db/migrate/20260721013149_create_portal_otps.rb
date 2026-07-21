class CreatePortalOtps < ActiveRecord::Migration[7.0]
  def change
    create_table :portal_otps do |t|
      t.citext :email, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :portal_otps, [:email, :created_at]
  end
end
