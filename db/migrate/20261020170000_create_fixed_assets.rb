# Le registre des immobilisations et leurs dotations (revue expert-comptable du
# 2026-10-20 : « pas de registre d'immobilisations ni d'amortissements »).
#
# Une immobilisation dit trois comptes : où elle est à l'actif (240000), où
# s'accumulent ses amortissements (240001, le 2x9 du PCMN) et où se passe la
# dotation (630100). Une dotation est une ligne par immobilisation et par
# exercice : c'est elle la pièce de l'écriture, et l'index unique interdit de
# doter deux fois la même année.
class CreateFixedAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :fixed_assets do |t|
      t.references :legal_entity, null: false, foreign_key: true
      t.references :general_account, null: false, foreign_key: true
      t.references :depreciation_account, null: false, foreign_key: { to_table: :general_accounts }
      t.references :expense_account, null: false, foreign_key: { to_table: :general_accounts }
      t.references :team, foreign_key: true
      t.string :name, null: false
      t.date :acquired_on, null: false
      t.bigint :acquisition_cents, null: false
      t.integer :useful_life_years, null: false
      t.bigint :prior_depreciation_cents, null: false, default: 0
      t.date :disposed_on
      t.text :notes
      t.datetime :deleted_at, index: true
      t.timestamps
    end

    create_table :fixed_asset_depreciations do |t|
      t.references :fixed_asset, null: false, foreign_key: true
      t.references :fiscal_year, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.timestamps
      t.index %i[fixed_asset_id fiscal_year_id], unique: true, name: "index_fixed_asset_depreciations_unique_year"
    end
  end
end
