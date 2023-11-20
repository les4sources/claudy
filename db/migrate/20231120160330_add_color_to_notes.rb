class AddColorToNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :notes, :color, :string
  end
end
