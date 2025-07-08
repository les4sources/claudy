class AddCompanyAndAddressFieldsToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :company_name, :string
    add_column :customers, :vat_number, :string
    add_column :customers, :street, :string
    add_column :customers, :number, :string
    add_column :customers, :box, :string
    add_column :customers, :postcode, :string
    add_column :customers, :city, :string
    add_column :customers, :country, :string, default: "Belgique"
  end
end
