json.data { json.partial! "api/v1/cash_entries/cash_entry", cash_entry: @cash_entry }
json.meta do
  json.created @created unless @created.nil?
  # Le solde du compte APRÈS la ligne : c'est ce qui permet de recouper une
  # reprise sans relire tout le journal.
  json.cash_account_balance_cents CashEntry.where(cash_account_id: @cash_entry.cash_account_id).sum(:amount_cents)
end
