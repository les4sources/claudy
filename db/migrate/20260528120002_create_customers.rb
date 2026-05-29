class CreateCustomers < ActiveRecord::Migration[7.0]
  def change
    create_table :customers do |t|
      t.string :first_name
      t.string :last_name
      t.citext :email
      t.string :phone
      t.string :customer_type, default: "individual", null: false
      t.string :organization_name
      t.string :vat_number
      t.string :peppol_id
      t.string :address_line
      t.string :address_zip
      t.string :address_city
      t.string :address_country
      t.string :language, default: "fr", null: false
      t.string :stripe_customer_id
      t.boolean :marketing_consent, default: false, null: false
      t.boolean :nps_eligible, default: false, null: false
      t.references :human, foreign_key: true, null: true
      t.datetime :deleted_at

      t.timestamps
    end

    # Unique on email (citext makes it case-insensitive). Partial index so two
    # soft-deleted records with the same email don't collide — only live rows
    # are constrained to be unique.
    add_index :customers, :email, unique: true, where: "deleted_at IS NULL", name: "index_customers_on_email_unique_live"
    add_index :customers, :customer_type
  end
end
