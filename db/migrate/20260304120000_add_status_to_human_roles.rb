class AddStatusToHumanRoles < ActiveRecord::Migration[7.0]
  def change
    add_column :human_roles, :status, :integer, default: 1, null: false
  end
end
