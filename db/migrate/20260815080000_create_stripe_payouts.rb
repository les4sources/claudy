# Versements Stripe et leurs transactions (issue #187).
#
# Le problème que ces deux tables résolvent : Stripe verse le NET. Une ligne
# bancaire de 1 243,17 € ne correspond à aucune facture — c'est la somme de
# plusieurs paiements moins des frais. Sans le détail du versement, la seule
# façon de comptabiliser est une « opération diverse » saisie à la main, et
# c'est précisément pour ça que les commissions 2026 ne sont ventilées nulle
# part.
#
# `external_ref` porte l'identifiant Stripe : c'est lui qui rend la
# synchronisation rejouable sans doubler quoi que ce soit.
class CreateStripePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_payouts do |t|
      t.string :account_key, null: false
      t.references :cash_account, foreign_key: true
      t.string :stripe_id, null: false
      t.bigint :amount_cents, null: false
      t.date :arrival_date
      t.string :status
      t.string :currency, null: false, default: "EUR"
      t.datetime :synced_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stripe_payouts, [:account_key, :stripe_id], unique: true
    add_index :stripe_payouts, :arrival_date
    add_index :stripe_payouts, :deleted_at

    create_table :stripe_balance_transactions do |t|
      t.references :stripe_payout, null: false, foreign_key: true
      t.string :stripe_id, null: false
      t.string :kind, null: false
      t.bigint :gross_cents, null: false, default: 0
      t.bigint :fee_cents, null: false, default: 0
      t.bigint :net_cents, null: false, default: 0
      # `payments.id` est un uuid (issue #52) — la référence doit le suivre,
      # sinon la contrainte de clé étrangère ne peut pas exister.
      t.references :payment, type: :uuid, foreign_key: true
      t.string :category
      t.string :description
      t.datetime :occurred_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stripe_balance_transactions, :stripe_id, unique: true
    add_index :stripe_balance_transactions, :deleted_at
  end
end
