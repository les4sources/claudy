class AddRestrictedToExperiencesToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :restricted_to_experiences, :boolean, default: false, null: false
  end
end
