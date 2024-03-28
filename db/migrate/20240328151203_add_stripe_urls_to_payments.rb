class AddStripeUrlsToPayments < ActiveRecord::Migration[7.0]
  def change
    add_column :payments, :stripe_checkout_session_id, :string
    add_column :payments, :stripe_payment_intent_id, :string
  end
end
