class AddGroupNameToStay < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :group_name, :string
  end
end
