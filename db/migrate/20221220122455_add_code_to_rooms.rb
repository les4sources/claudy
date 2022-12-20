class AddCodeToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :code, :string
  end
end
