class AddCommentsToStay < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :comments, :text
  end
end
