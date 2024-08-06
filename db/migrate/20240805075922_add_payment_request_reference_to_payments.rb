class AddPaymentRequestReferenceToPayments < ActiveRecord::Migration[7.0]
  def change
    add_reference :payments, :payment_request, null: true, foreign_key: true
  end
end
