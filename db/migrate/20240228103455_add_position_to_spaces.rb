class AddPositionToSpaces < ActiveRecord::Migration[7.0]
  def change
    add_column :spaces, :position, :integer, default: 999
  end
end
