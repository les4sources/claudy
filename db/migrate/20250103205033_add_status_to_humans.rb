class AddStatusToHumans < ActiveRecord::Migration[7.0]
  def change
    add_column :humans, :status, :string, default: "active"
  end
end
