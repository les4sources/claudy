class AddPublicNotesToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :public_notes, :text
  end
end
