class AddSummaryToLodgings < ActiveRecord::Migration[7.0]
  def change
    add_column :lodgings, :summary, :string
  end
end
