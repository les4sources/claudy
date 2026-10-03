# Epic #359, phase 4 — la banque des carnets de l'épicerie.
#
# Deux choses : une ligne bancaire sait désormais à quel artisan elle revient
# (`cash_entries.consignor_id`), et les réglages des carnets portent la
# correspondance canal → compte de produit d'où naissent les règles
# d'affectation par mot-clé (EPICERIE, PAIN, ARTISANAT <PRÉNOM>).
class AddBankLinksForShopNotebooks < ActiveRecord::Migration[8.1]
  def change
    add_reference :cash_entries, :consignor, foreign_key: true, index: true

    add_reference :shop_settings, :grocery_account, foreign_key: { to_table: :general_accounts }, index: true
    add_reference :shop_settings, :bread_account,   foreign_key: { to_table: :general_accounts }, index: true
    add_reference :shop_settings, :craft_account,   foreign_key: { to_table: :general_accounts }, index: true
  end
end
