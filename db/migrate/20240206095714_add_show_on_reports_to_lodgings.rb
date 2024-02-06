class AddShowOnReportsToLodgings < ActiveRecord::Migration[7.0]
  def change
    add_column :lodgings, :show_on_reports, :boolean, default: true
  end
end
