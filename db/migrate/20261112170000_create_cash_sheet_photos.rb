# La photo de la feuille papier de caisse (Michael, 2026-11-12) : chaque mois,
# on reprend la feuille tenue au bar pour compléter les lignes de la feuille de
# caisse. Sa photo (ou un PDF scanné) reste jointe au mois, pour référence.
# Une seule par caisse et par mois : en joindre une autre la remplace.
class CreateCashSheetPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_sheet_photos do |t|
      t.references :cash_account, null: false, foreign_key: true
      t.date :month, null: false
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :cash_sheet_photos, %i[cash_account_id month], unique: true
  end
end
