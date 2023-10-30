class AddFieldsToExperiences < ActiveRecord::Migration[7.0]
  def change
    add_column :experiences, :fixed_price_cents, :integer, default: 0
    add_column :experiences, :min_participants, :integer
    add_column :experiences, :max_participants, :integer
    add_column :experiences, :duration, :string
  end
end
