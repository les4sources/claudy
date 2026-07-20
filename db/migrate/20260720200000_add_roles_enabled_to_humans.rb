class AddRolesEnabledToHumans < ActiveRecord::Migration[7.0]
  def change
    add_column :humans, :roles_enabled, :boolean, default: true, null: false
  end
end
