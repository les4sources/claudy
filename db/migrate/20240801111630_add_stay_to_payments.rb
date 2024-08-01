class AddStayToPayments < ActiveRecord::Migration[7.0]
  def change
    add_reference :payments, :stay, null: true, foreign_key: true
    change_column_null :payments, :booking_id, true
  end
end
