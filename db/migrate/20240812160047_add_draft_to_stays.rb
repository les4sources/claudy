class AddDraftToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :draft, :boolean, default: true
  end
end
