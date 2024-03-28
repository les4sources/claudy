class CreatePaylinks < ActiveRecord::Migration[7.0]
  def change
    create_table :paylinks, id: :uuid do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :status
      t.string :checkout_url

      t.timestamps
    end

    add_monetize :paylinks, :amount, amount: { null: false }, currency: { present: false }
  end
end
