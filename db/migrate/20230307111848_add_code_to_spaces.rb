class AddCodeToSpaces < ActiveRecord::Migration[7.0]
  def change
    add_column :spaces, :code, :string
  end
end
