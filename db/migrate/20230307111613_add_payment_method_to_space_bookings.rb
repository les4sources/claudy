class AddPaymentMethodToSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    add_column :space_bookings, :payment_method, :string
  end
end
