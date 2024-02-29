class AddFieldsToEvents < ActiveRecord::Migration[7.0]
  def change
    add_monetize :events, :sales_amount, amount: { null: true, default: nil }, currency: { present: false }
    add_column :events, :attendees, :integer
    add_column :events, :notes, :text
    add_column :events, :status, :string
  end
end
