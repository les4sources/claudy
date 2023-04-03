class AddFieldsToSpaceBookings < ActiveRecord::Migration[7.0]
  def change
    add_monetize :space_bookings, :paid_amount, amount: { null: true, default: nil }, currency: { present: false }
    add_monetize :space_bookings, :deposit_amount, amount: { null: true, default: nil }, currency: { present: false }
    add_column :space_bookings, :persons, :string
    add_column :space_bookings, :arrival_time, :string
    add_column :space_bookings, :departure_time, :string
    add_column :bookings, :departure_time, :string
    add_column :space_bookings, :option_kitchenware, :boolean, default: false
    add_column :space_bookings, :option_beamer, :boolean, default: false
    add_column :space_bookings, :option_wifi, :boolean, default: false
    add_column :space_bookings, :option_tables, :boolean, default: false
  end
end
