class AddActivityColumnsToStays < ActiveRecord::Migration[7.0]
  def change
    add_column :stays, :activity_selection_token, :string
    add_index :stays, :activity_selection_token
    add_column :stays, :activity_email_sent_at, :datetime
  end
end
