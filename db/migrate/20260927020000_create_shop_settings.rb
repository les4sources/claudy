# Épicerie au papier (epic #359, phase 3) : les coordonnées bancaires des QR
# EPC imprimés sur les feuilles des carnets, et les compteurs de feuilles.
#
# Le dépôt est public : l'IBAN de la fondation ne vit jamais dans le code, il
# se règle dans l'admin. Une seule ligne dans cette table (`ShopSetting.current`).
#
# Côté artisan : une photo (`portrait`, Active Storage), une phrase de
# présentation et le compteur de ses feuilles imprimées.
class CreateShopSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_settings do |t|
      t.text :iban
      t.string :bic
      t.string :beneficiary_name
      t.integer :grocery_sheets_printed_count, null: false, default: 0
      t.integer :bread_sheets_printed_count, null: false, default: 0
      t.timestamps
    end

    add_column :consignors, :tagline, :string
    add_column :consignors, :sheets_printed_count, :integer, null: false, default: 0
  end
end
