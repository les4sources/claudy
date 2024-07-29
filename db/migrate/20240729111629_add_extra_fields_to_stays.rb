class AddExtraFieldsToStays < ActiveRecord::Migration[7.0]
  def change
     add_column :stays, :adults, :integer
     add_column :stays, :children, :integer
     add_column :stays, :babies, :integer
     add_column :stays, :estimated_arrival, :string
     add_column :stays, :departure_time, :string
     add_column :stays, :token, :string
  end 
end
