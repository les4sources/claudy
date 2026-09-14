# Le mode « grand livre » d'un compte Stripe (epic #250, phase 1).
#
# Stripe refuse `BalanceTransaction.list(payout: …)` sur un compte à versements
# MANUELS : il ne sait pas quelles ventes un versement couvre. Tout le code de
# l'issue #187 suppose l'inverse. D'où un second mode, où le solde Stripe est
# tenu comme un vrai compte de trésorerie : chaque transaction devient une ou
# deux lignes, et le versement devient un virement interne vers la banque.
class AddStripeLedgerMode < ActiveRecord::Migration[8.1]
  def change
    add_column :cash_accounts, :stripe_mode, :string, null: false, default: "per_payout"

    # Ce que Stripe dit du versement lui-même. C'est ce booléen qui permet de
    # refuser proprement l'import d'un compte manuel resté en mode `per_payout`,
    # au lieu de le laisser lever une exception au milieu du rake.
    add_column :stripe_payouts, :automatic, :boolean

    # En mode `ledger`, une transaction du solde n'appartient à AUCUN versement :
    # elle appartient au compte. La colonne devient donc facultative, et la
    # transaction porte elle-même son compte.
    change_column_null :stripe_balance_transactions, :stripe_payout_id, true
    add_column :stripe_balance_transactions, :account_key, :string
    add_reference :stripe_balance_transactions, :cash_account, foreign_key: true
    add_column :stripe_balance_transactions, :available_on, :date
    add_index :stripe_balance_transactions, %i[account_key occurred_at]

    # L'affectation se décide une fois par catégorie, jamais par transaction
    # (décision 4). `category` nul désigne « les transactions sans catégorie » —
    # d'où deux index plutôt qu'un : en Postgres, NULL n'entre pas en collision
    # avec NULL dans un index unique ordinaire.
    create_table :stripe_category_mappings do |t|
      t.string :account_key, null: false
      t.string :category
      t.references :general_account, null: false, foreign_key: true
      t.references :team, foreign_key: true
      t.references :legal_entity, foreign_key: true
      t.text :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stripe_category_mappings, %i[account_key category],
              unique: true, where: "category IS NOT NULL AND deleted_at IS NULL",
              name: "index_stripe_category_mappings_on_account_and_category"
    add_index :stripe_category_mappings, :account_key,
              unique: true, where: "category IS NULL AND deleted_at IS NULL",
              name: "index_stripe_category_mappings_on_account_without_category"
    add_index :stripe_category_mappings, :deleted_at

    # D'où vient une ligne de trésorerie. Nommé `source` comme le `source` des
    # écritures : une écriture pointe la ligne qui l'a produite, une ligne pointe
    # le fait qui l'a produite. Facultatif — une ligne CODA n'en a pas.
    add_reference :cash_entries, :source, polymorphic: true, index: true
  end
end
