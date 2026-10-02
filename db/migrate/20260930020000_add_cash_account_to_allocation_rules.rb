# Une règle peut se limiter à un compte de trésorerie (issue #392). Sans
# restriction, elle reste valable partout : aucune règle existante ne bouge.
class AddCashAccountToAllocationRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :allocation_rules, :cash_account, null: true, index: true, foreign_key: true
  end
end
