json.data { json.partial! "api/v1/cash_accounts/cash_account", cash_account: @cash_account }
json.meta { json.created @created } unless @created.nil?
