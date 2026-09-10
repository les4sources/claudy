# Le tiers gagne de quoi le payer et le facturer (epic #240, phase 1). L'IBAN
# est chiffré au repos comme celui d'un artisan : une coordonnée bancaire n'a
# pas à être lisible dans un dump de base.
class AddContactDetailsToThirdParties < ActiveRecord::Migration[8.1]
  def change
    add_column :third_parties, :iban, :string
    add_column :third_parties, :vat_number, :string
    add_column :third_parties, :email, :string
    add_column :third_parties, :notes, :text
  end
end
