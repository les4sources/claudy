json.data { json.partial! "api/v1/account_entries/account_entry", account_entry: @account_entry }
json.meta do
  json.created @created unless @created.nil?
  # Le solde du compte APRÈS l'écriture : c'est ce qui permet à l'appelant de
  # vérifier sa reprise sans relire tout le grand livre.
  json.member_account_balance_cents @account_entry.member_account.reload.balance_cents
end
