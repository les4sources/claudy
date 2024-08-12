class ChangeCustomerIdForStays < ActiveRecord::Migration[7.0]
  def change
    change_column_null :stays, :customer_id, true
  end
end
