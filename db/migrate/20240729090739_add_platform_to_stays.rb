class AddPlatformToStays < ActiveRecord::Migration[7.0]
   def change
    add_column :stays, :platform, :string
  end
end
