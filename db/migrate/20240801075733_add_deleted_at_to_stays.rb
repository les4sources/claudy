class AddDeletedAtToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :deleted_at, :timestamp
  end
end
