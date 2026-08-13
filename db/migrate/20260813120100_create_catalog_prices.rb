# Paliers de prix datés (issue #157).
#
# QUATRE prix sont stockés EXPLICITEMENT — achat, référence, sourcier, public —
# et jamais dérivés à la lecture. Les deux règles métier vont en sens opposé :
# au bar le prix sourcier se calcule sur l'ACHAT majoré (2,10 € pour une
# Moinette achetée 1,91 €, quand le public paie 4,00 €), au cellier il se
# calcule sur une RÉFÉRENCE minorée (2,80 € pour une avoine de référence
# 2,95 €, le public payant 3,10 €). Dériver à la lecture avec deux règles de
# sens contraire, c'est garantir qu'un jour quelqu'un appliquera la majoration
# du bar à un prix public sans que personne ne le voie.
#
# Les coefficients (`bar.member_markup`, `grocery.member_ratio`,
# `grocery.public_ratio`) ne servent donc QU'au générateur qui propose un
# nouveau palier. Ce qui est enregistré est un montant.
class CreateCatalogPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_prices do |t|
      t.references :catalog_item, null: false, foreign_key: true
      t.date :active_from, null: false
      t.date :active_until
      t.integer :purchase_price_cents
      t.integer :reference_price_cents
      t.integer :member_price_cents, null: false
      t.integer :public_price_cents
      t.string :note

      t.timestamps
    end

    add_index :catalog_prices, [:catalog_item_id, :active_from], unique: true
  end
end
