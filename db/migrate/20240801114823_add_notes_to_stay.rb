class AddNotesToStay < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :notes, :text
  end
end
