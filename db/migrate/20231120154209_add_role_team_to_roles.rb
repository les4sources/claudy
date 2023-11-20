class AddRoleTeamToRoles < ActiveRecord::Migration[7.0]
  def change
    add_column :roles, :role_team, :jsonb, default: []
    # Add an index for better performance
    add_index :roles, :role_team, using: :gin
  end
end
