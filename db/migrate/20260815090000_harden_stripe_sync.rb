# Les gardes réclamées par la revue adverse (issue #187).
#
# Les index uniques incluaient les lignes soft-deletées : après une suppression
# logique, `find_by` ne voyait plus le versement et la resynchronisation
# échouait sur l'unicité. Une idempotence qui casse dès qu'on a supprimé quelque
# chose n'est pas une idempotence.
#
# Et le compte de trésorerie était choisi « le premier de type stripe » : avec
# deux comptes Stripe, les flux de Tranche de Vie pouvaient atterrir sur le
# compte de Claudy. La clé de compte est désormais portée explicitement.
class HardenStripeSync < ActiveRecord::Migration[8.1]
  def change
    remove_index :stripe_payouts, column: [:account_key, :stripe_id]
    add_index :stripe_payouts, [:account_key, :stripe_id],
              unique: true, where: "deleted_at IS NULL",
              name: "index_stripe_payouts_on_account_and_id"

    remove_index :stripe_balance_transactions, column: :stripe_id
    add_index :stripe_balance_transactions, :stripe_id,
              unique: true, where: "deleted_at IS NULL",
              name: "index_stripe_transactions_on_stripe_id"

    add_column :cash_accounts, :stripe_account_key, :string
    add_index :cash_accounts, :stripe_account_key, unique: true, where: "stripe_account_key IS NOT NULL"
  end
end
