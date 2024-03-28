class RemovePaymentsNumericId < ActiveRecord::Migration[7.0]
  def change
    remove_column :payments, :numeric_id
  end
end
