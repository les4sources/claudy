# Dettes et litiges (2026-10-13) : ce que la maison doit ou risque de devoir
# SANS facture encodée — la taxe communale d'hébergement qu'Yvoir réclame pour
# cinq ans, un arriéré, une contestation en cours. Le montant réclamé, la
# fourchette de ce qu'on paiera vraiment, et le montant RETENU pour la gestion :
# c'est lui que la trésorerie retire, à la date probable, en une fois ou étalé.
#
# Comme les charges fixes, rien n'est comptabilisé ici : c'est de la gestion.
# La provision (classe 16) reste un geste du comptable à la clôture.
class CreateLiabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :liabilities do |t|
      t.references :legal_entity, null: false, foreign_key: true
      t.references :third_party, foreign_key: true
      t.references :team, foreign_key: true
      t.references :general_account, foreign_key: true
      t.string :label, null: false
      t.string :kind, null: false, default: "debt"
      t.bigint :claimed_cents
      t.bigint :low_cents
      t.bigint :high_cents
      t.bigint :retained_cents, null: false
      t.bigint :paid_cents, null: false, default: 0
      t.date :expected_on
      t.integer :installments, null: false, default: 1
      t.string :status, null: false, default: "open"
      t.date :closed_on
      t.text :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :liabilities, :deleted_at
    add_index :liabilities, :status
  end
end
