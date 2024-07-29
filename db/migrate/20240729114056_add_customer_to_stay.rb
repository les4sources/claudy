class AddCustomerToStay < ActiveRecord::Migration[7.0]
  def change
    add_reference :stays, :customer, null: false, foreign_key: true
  end
end
